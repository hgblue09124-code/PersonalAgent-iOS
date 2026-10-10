import Foundation
import PAKernel
import PAProviders
import PAGGUF
#if canImport(cllama)
import cllama
#endif

/// Concrete native llama.cpp local inference engine for PersonalAgent.
public final class LlamaCPPModelEngine: LocalModelEngine, @unchecked Sendable {
    public let identity: LocalModelIdentity
    private let deviceCapabilityProvider: any DeviceCapabilityProviding
    private let residencyCoordinator: LlamaCPPResidencyCoordinator
    private let parser = GGUFModelParser()

    private let streamRunner: (@Sendable (LocalModelGenerationRequest, AsyncThrowingStream<LocalModelStreamChunk, Error>.Continuation) async throws -> Int)?
    private let stateLock = NSLock()
    private var currentLifecycleState: LocalModelLifecycleState = .unloaded
    private var activeOptions: LocalModelLoadingOptions?
    private var activeGenerationTask: Task<Void, Never>?
    private var generationInFlight = false
    private var parsedMetadata: GGUFMetadataSummary?

    // Native llama.cpp handles
    private var nativeModel: OpaquePointer?
    private var nativeContext: OpaquePointer?
    #if canImport(cllama)
    private var nativeSampler: UnsafeMutablePointer<llama_sampler>?
    #else
    private var nativeSampler: OpaquePointer?
    #endif

    public init(
        identity: LocalModelIdentity,
        deviceCapabilityProvider: (any DeviceCapabilityProviding)? = nil,
        residencyCoordinator: LlamaCPPResidencyCoordinator = .shared,
        streamRunner: (@Sendable (LocalModelGenerationRequest, AsyncThrowingStream<LocalModelStreamChunk, Error>.Continuation) async throws -> Int)? = nil
    ) {
        self.identity = identity
        self.deviceCapabilityProvider = deviceCapabilityProvider ?? DefaultDeviceCapabilityProvider()
        self.residencyCoordinator = residencyCoordinator
        self.streamRunner = streamRunner
    }

    deinit {
        releaseNativeHandles()
    }

    public var availability: LocalModelAvailability {
        get async {
            guard let url = identity.localURL else {
                return .notDownloaded
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .notDownloaded
            }
            return .ready
        }
    }

    public var lifecycleState: LocalModelLifecycleState {
        get async {
            stateLock.withLock { currentLifecycleState }
        }
    }

    public func load(options: LocalModelLoadingOptions) async throws {
        let state = stateLock.withLock { currentLifecycleState }
        guard state == .unloaded || isFailedState(state) else {
            if state == .loaded { return }
            throw LlamaCPPEngineError.modelAlreadyLoaded
        }

        setLifecycleState(.loading(progress: 0.1))

        // 1. Verify model file availability
        guard let url = identity.localURL else {
            setLifecycleState(.failed(reason: "No model URL provided"))
            throw LlamaCPPEngineError.invalidModelURL
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            setLifecycleState(.failed(reason: "Model file not found at \(url.path)"))
            throw LlamaCPPEngineError.modelFileNotFound(url)
        }

        // 2. Parse GGUF metadata for validation
        let summary: GGUFMetadataSummary
        do {
            summary = try parser.parseHeaderAndMetadata(at: url)
        } catch {
            setLifecycleState(.failed(reason: "GGUF header parse failed: \(error.localizedDescription)"))
            throw error
        }

        setLifecycleState(.loading(progress: 0.4))

        // 3. Enforce single-resident-model invariant across coordinator
        do {
            try await residencyCoordinator.requestResidency(for: self)
        } catch {
            setLifecycleState(.failed(reason: error.localizedDescription))
            throw error
        }

        setLifecycleState(.loading(progress: 0.6))

        // 4. Real native model and context initialization via llama.cpp
        #if canImport(cllama)
        do {
            llama_backend_init()

            var modelParams = llama_model_default_params()
            if let gL = options.gpuLayers {
                modelParams.n_gpu_layers = Int32(gL)
            }

            let path = url.path
            guard let modelPtr = llama_model_load_from_file(path, modelParams) else {
                throw LlamaCPPEngineError.nativeModelLoadFailed(path)
            }

            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = UInt32(options.contextWindow)

            let nThreads = options.threadCount ?? max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
            ctxParams.n_threads = Int32(nThreads)
            ctxParams.n_threads_batch = Int32(nThreads)

            guard let contextPtr = llama_init_from_model(modelPtr, ctxParams) else {
                llama_model_free(modelPtr)
                throw LlamaCPPEngineError.nativeContextCreationFailed
            }

            // Initialize sampler chain and configure real samplers
            let chainParams = llama_sampler_chain_default_params()
            guard let samplerPtr = llama_sampler_chain_init(chainParams) else {
                llama_free(contextPtr)
                llama_model_free(modelPtr)
                throw LlamaCPPEngineError.nativeContextCreationFailed
            }

            // Configure greedy sampler by default in the chain
            llama_sampler_chain_add(samplerPtr, llama_sampler_init_greedy())

            setLifecycleState(.loading(progress: 0.95))

            stateLock.withLock {
                self.nativeModel = modelPtr
                self.nativeContext = contextPtr
                self.nativeSampler = samplerPtr
                self.parsedMetadata = summary
                self.activeOptions = options
                self.currentLifecycleState = .loaded
            }
        } catch {
            await residencyCoordinator.releaseResidency(for: identity.id)
            setLifecycleState(.failed(reason: error.localizedDescription))
            throw error
        }
        #else
        await residencyCoordinator.releaseResidency(for: identity.id)
        setLifecycleState(.failed(reason: "cllama target is supported on Apple platforms"))
        throw LlamaCPPEngineError.nativeModelLoadFailed(url.path)
        #endif
    }

    public func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
        var text = ""
        var finishReason = "stop"
        let stream = generateStream(request: request)

        for try await chunk in stream {
            text += chunk.textDelta
            if let reason = chunk.finishReason {
                finishReason = reason
            }
        }

        try LocalModelOutputValidator.validate(text: text)

        return LocalModelResponse(
            text: text,
            finishReason: finishReason,
            promptTokens: request.prompt.count / 4,
            completionTokens: text.count / 4
        )
    }

    public func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
        let (stream, continuation) = AsyncThrowingStream<LocalModelStreamChunk, Error>.makeStream()

        let admitted = stateLock.withLock { () -> Bool in
            guard !generationInFlight else { return false }
            generationInFlight = true
            return true
        }
        guard admitted else {
            continuation.finish(throwing: LlamaCPPEngineError.generationInProgress)
            return stream
        }

        let task = Task {
            defer { self.clearGenerationTask() }
            do {
                if let runner = self.streamRunner {
                    let (capturedStream, capturedContinuation) = AsyncThrowingStream<LocalModelStreamChunk, Error>.makeStream()
                    let forwardingTask = Task {
                        var streamedText = ""
                        do {
                            for try await chunk in capturedStream {
                                streamedText += chunk.textDelta
                                continuation.yield(chunk)
                            }
                            return streamedText
                        } catch {
                            throw error
                        }
                    }

                    do {
                        let generatedCount = try await runner(request, capturedContinuation)
                        capturedContinuation.finish()
                        let streamedText = try await forwardingTask.value
                        try LocalModelOutputValidator.validate(text: streamedText, generatedCount: generatedCount)
                    } catch {
                        capturedContinuation.finish(throwing: error)
                        _ = try? await forwardingTask.value
                        throw error
                    }

                    if self.isLoaded() {
                        self.setLifecycleState(.loaded)
                    }
                    continuation.finish()
                    return
                }

                // Verify loaded state and obtain native pointers
                #if canImport(cllama)
                guard let (modelPtr, contextPtr, samplerPtr) = self.getNativeHandles() else {
                    throw LlamaCPPEngineError.modelNotLoaded
                }

                // Verify device thermal & memory state
                let thermal = await self.deviceCapabilityProvider.thermalState
                if thermal == .critical {
                    throw LlamaCPPEngineError.thermalStateCritical
                }

                let memory = await self.deviceCapabilityProvider.memoryPressure
                if memory == .critical {
                    _ = try? await self.unload()
                    throw LlamaCPPEngineError.memoryPressureCritical
                }

                // Each Agent request is an independent turn.
                // The Agent currently does not persist a conversational KV history,
                // so reusing the previous context would make the next request attend
                // to stale tokens and can produce repeated or nonsensical output.
                llama_memory_clear(llama_get_memory(contextPtr), true)
                llama_sampler_reset(samplerPtr)

                // Format the semantic system/user request with the model's own
                // GGUF chat template. The native path must not hand raw role text
                // to the tokenizer: instruct models otherwise commonly echo it.
                let promptText = try self.makePrompt(
                    model: modelPtr,
                    systemPrompt: request.systemPrompt,
                    userPrompt: request.prompt
                )

                guard let vocabPtr = llama_model_get_vocab(modelPtr) else {
                    throw LlamaCPPEngineError.tokenizationFailed
                }

                let promptTokens = try self.tokenize(vocab: vocabPtr, text: promptText, addSpecial: true)
                guard !promptTokens.isEmpty else {
                    throw LlamaCPPEngineError.tokenizationFailed
                }

                // 2. Decode prompt batch
                var batch = llama_batch_init(Int32(promptTokens.count), 0, 1)
                defer { llama_batch_free(batch) }

                for (i, tok) in promptTokens.enumerated() {
                    let isLast = (i == promptTokens.count - 1)
                    self.addTokenToBatch(&batch, id: tok, pos: Int32(i), seqID: 0, logits: isLast)
                }

                let evalRes = llama_decode(contextPtr, batch)
                guard evalRes == 0 else {
                    throw LlamaCPPEngineError.evalFailed(evalRes)
                }

                // 3. Generation loop
                let contextWindow = stateLock.withLock { activeOptions?.contextWindow ?? identity.contextTokenLimit }
                guard promptTokens.count < contextWindow else {
                    throw LlamaCPPEngineError.contextWindowExceeded
                }
                let requestedMaxTokens = request.maxTokens ?? 512
                let maxTokens = min(requestedMaxTokens, contextWindow - promptTokens.count)
                guard maxTokens > 0 else {
                    throw LlamaCPPEngineError.contextWindowExceeded
                }
                var currentPos = Int32(promptTokens.count)
                var generatedCount = 0
                var streamedText = ""

                var invalidBytes: [CChar] = []

                while generatedCount < maxTokens {
                    if Task.isCancelled {
                        throw LlamaCPPEngineError.cancelled
                    }

                    // Mid-generation thermal/memory checks
                    let currentThermal = await self.deviceCapabilityProvider.thermalState
                    if currentThermal == .critical {
                        throw LlamaCPPEngineError.thermalStateCritical
                    }
                    let currentMemory = await self.deviceCapabilityProvider.memoryPressure
                    if currentMemory == .critical {
                        _ = try? await self.unload()
                        throw LlamaCPPEngineError.memoryPressureCritical
                    }

                    // Sample next token
                    let nextToken = llama_sampler_sample(samplerPtr, contextPtr, batch.n_tokens - 1)

                    // Check EOS / EOG
                    if llama_vocab_is_eog(vocabPtr, nextToken) {
                        let chunk = LocalModelStreamChunk(textDelta: "", finishReason: "stop")
                        continuation.yield(chunk)
                        break
                    }

                    // Decode token piece
                    let pieceBytes = self.tokenToPiece(vocab: vocabPtr, token: nextToken)
                    invalidBytes.append(contentsOf: pieceBytes)

                    let deltaText: String
                    if let str = String(validatingCString: invalidBytes + [0]) {
                        invalidBytes.removeAll()
                        deltaText = str
                    } else if let validLen = (0 ..< invalidBytes.count).first(where: { len in len != 0 && String(validatingCString: Array(invalidBytes.suffix(len)) + [0]) != nil }) {
                        deltaText = String(validatingCString: Array(invalidBytes.suffix(validLen)) + [0]) ?? ""
                        invalidBytes.removeAll()
                    } else {
                        deltaText = ""
                    }

                    generatedCount += 1
                    let isLastToken = (generatedCount >= maxTokens)
                    streamedText += deltaText
                    let chunk = LocalModelStreamChunk(
                        textDelta: deltaText,
                        finishReason: isLastToken ? "length" : nil
                    )
                    continuation.yield(chunk)

                    if isLastToken {
                        break
                    }

                    // Decode next step
                    self.clearBatch(&batch)
                    self.addTokenToBatch(&batch, id: nextToken, pos: currentPos, seqID: 0, logits: true)
                    currentPos += 1

                    let stepEval = llama_decode(contextPtr, batch)
                    guard stepEval == 0 else {
                        throw LlamaCPPEngineError.evalFailed(stepEval)
                    }

                    if currentThermal == .serious {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                }

                try LocalModelOutputValidator.validate(text: streamedText, generatedCount: generatedCount)

                if self.isLoaded() {
                    self.setLifecycleState(.loaded)
                }
                continuation.finish()
                #else
                throw LlamaCPPEngineError.modelNotLoaded
                #endif
            } catch {
                if self.isLoaded() {
                    self.setLifecycleState(.loaded)
                }
                continuation.finish(throwing: error)
            }
        }

        stateLock.withLock {
            self.activeGenerationTask = task
        }

        continuation.onTermination = { _ in
            // Cancellation requests the generation task to stop. The task's
            // defer owns generationInFlight cleanup so a new request cannot
            // race the still-running native generation.
            task.cancel()
        }

        return stream
    }

    public func cancel() async {
        let task = stateLock.withLock {
            let t = activeGenerationTask
            activeGenerationTask = nil
            return t
        }
        task?.cancel()
        await task?.value
    }

    public func unload() async throws {
        setLifecycleState(.unloading)
        await cancel()
        await residencyCoordinator.releaseResidency(for: identity.id)
        releaseNativeHandles()
        stateLock.withLock {
            activeOptions = nil
            parsedMetadata = nil
            currentLifecycleState = .unloaded
        }
    }

    // MARK: - Private Helpers

    #if canImport(cllama)
    private func makePrompt(
        model: OpaquePointer,
        systemPrompt: String?,
        userPrompt: String
    ) throws -> String {
        func render(_ messages: [llama_chat_message]) throws -> String {
            guard let template = llama_model_chat_template(model, nil) else {
                return userPrompt
            }

            var chat = messages
            let required = chat.withUnsafeMutableBufferPointer { buffer in
                llama_chat_apply_template(
                    template,
                    buffer.baseAddress,
                    buffer.count,
                    true,
                    nil,
                    0
                )
            }
            guard required >= 0 else {
                throw LlamaCPPEngineError.tokenizationFailed
            }

            var output = Array(repeating: CChar(0), count: Int(required) + 1)
            let outputCapacity = output.count
            let written = chat.withUnsafeMutableBufferPointer { buffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    llama_chat_apply_template(
                        template,
                        buffer.baseAddress,
                        buffer.count,
                        true,
                        outputBuffer.baseAddress,
                        Int32(outputCapacity)
                    )
                }
            }
            guard written >= 0, written <= output.count else {
                throw LlamaCPPEngineError.tokenizationFailed
            }
            return String(decoding: output.prefix(Int(written)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        }

        if let systemPrompt, !systemPrompt.isEmpty {
            return try systemPrompt.withCString { systemPtr in
                try userPrompt.withCString { userPtr in
                    try render([
                        llama_chat_message(role: "system", content: systemPtr),
                        llama_chat_message(role: "user", content: userPtr),
                    ])
                }
            }
        }

        return try userPrompt.withCString { userPtr in
            try render([
                llama_chat_message(role: "user", content: userPtr),
            ])
        }
    }
    #endif

    private func isLoaded() -> Bool {
        stateLock.withLock {
            if case .loaded = currentLifecycleState { return true }
            return false
        }
    }

    private func isFailedState(_ state: LocalModelLifecycleState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func setLifecycleState(_ state: LocalModelLifecycleState) {
        stateLock.withLock {
            self.currentLifecycleState = state
        }
    }

    private func clearGenerationTask() {
        stateLock.withLock {
            self.activeGenerationTask = nil
            self.generationInFlight = false
        }
    }

    #if canImport(cllama)
    private func getNativeHandles() -> (OpaquePointer, OpaquePointer, UnsafeMutablePointer<llama_sampler>)? {
        stateLock.withLock {
            guard let m = nativeModel, let c = nativeContext, let s = nativeSampler else {
                return nil
            }
            return (m, c, s)
        }
    }
    #else
    private func getNativeHandles() -> (OpaquePointer, OpaquePointer, OpaquePointer)? {
        stateLock.withLock {
            guard let m = nativeModel, let c = nativeContext, let s = nativeSampler else {
                return nil
            }
            return (m, c, s)
        }
    }
    #endif

    private func releaseNativeHandles() {
        #if canImport(cllama)
        stateLock.withLock {
            if let s = nativeSampler {
                llama_sampler_free(s)
                nativeSampler = nil
            }
            if let c = nativeContext {
                llama_free(c)
                nativeContext = nil
            }
            if let m = nativeModel {
                llama_model_free(m)
                nativeModel = nil
            }
            llama_backend_free()
        }
        #endif
    }

    #if canImport(cllama)
    private func tokenize(vocab: OpaquePointer, text: String, addSpecial: Bool) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        let maxTokens = utf8Count + (addSpecial ? 1 : 0) + 16
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        let count = llama_tokenize(vocab, text, Int32(utf8Count), &tokens, Int32(maxTokens), addSpecial, false)
        guard count >= 0 else {
            throw LlamaCPPEngineError.tokenizationFailed
        }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> [CChar] {
        var buf = [CChar](repeating: 0, count: 16)
        let nTokens = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        if nTokens < 0 {
            var biggerBuf = [CChar](repeating: 0, count: Int(-nTokens))
            let _ = llama_token_to_piece(vocab, token, &biggerBuf, -nTokens, 0, false)
            return biggerBuf
        }
        return Array(buf.prefix(Int(nTokens)))
    }

    private func addTokenToBatch(_ batch: inout llama_batch, id: llama_token, pos: Int32, seqID: Int32, logits: Bool) {
        let idx = Int(batch.n_tokens)
        batch.token?[idx] = id
        batch.pos?[idx] = pos
        batch.n_seq_id?[idx] = 1
        batch.seq_id?[idx]?[0] = seqID
        batch.logits?[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    private func clearBatch(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }
    #endif
}
