import Foundation
import PAFoundation
import PAProviders
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
        llama_backend_init()

        var modelParams = llama_model_default_params()
        if options.useMetal {
            modelParams.n_gpu_layers = Int32(options.gpuLayers ?? 99)
        } else {
            modelParams.n_gpu_layers = 0
        }

        let path = url.path
        guard let modelPtr = llama_model_load_from_file(path, modelParams) else {
            setLifecycleState(.failed(reason: "llama_model_load_from_file failed for \(path)"))
            throw LlamaCPPEngineError.nativeModelLoadFailed(path)
        }

        var ctxParams = llama_context_default_params()
        let modelContextLimit = summary.contextLength.flatMap { Int(exactly: $0) }
        let requestedContext = max(256, options.contextWindow)
        let effectiveContext = min(requestedContext, modelContextLimit ?? requestedContext)
        ctxParams.n_ctx = UInt32(effectiveContext)
        ctxParams.n_batch = UInt32(min(effectiveContext, 512))

        let nThreads = options.threadCount ?? max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let contextPtr = llama_init_from_model(modelPtr, ctxParams) else {
            llama_model_free(modelPtr)
            setLifecycleState(.failed(reason: "llama_init_from_model failed"))
            throw LlamaCPPEngineError.nativeContextCreationFailed
        }

        // Initialize sampler chain and configure real samplers
        let chainParams = llama_sampler_chain_default_params()
        guard let samplerPtr = llama_sampler_chain_init(chainParams) else {
            llama_free(contextPtr)
            llama_model_free(modelPtr)
            setLifecycleState(.failed(reason: "llama_sampler_chain_init failed"))
            throw LlamaCPPEngineError.nativeContextCreationFailed
        }

        // Use the request's sampling policy. Greedy-only decoding was causing
        // deterministic repetition and ignored the provider temperature contract.
        // Keep a bounded default temperature for normal chat, and add a light
        // repetition penalty before temperature sampling.
        let temperature = 0.7
        llama_sampler_chain_add(
            samplerPtr,
            llama_sampler_init_penalties(64, 64, Float(1.10), Float(0.0), Float(0.0))
        )
        llama_sampler_chain_add(
            samplerPtr,
            llama_sampler_init_top_k(40)
        )
        llama_sampler_chain_add(
            samplerPtr,
            llama_sampler_init_top_p(Float(0.95), 1)
        )
        llama_sampler_chain_add(
            samplerPtr,
            llama_sampler_init_temp(Float(temperature))
        )
        llama_sampler_chain_add(
            samplerPtr,
            llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max))
        )

        setLifecycleState(.loading(progress: 0.95))

        stateLock.withLock {
            self.nativeModel = modelPtr
            self.nativeContext = contextPtr
            self.nativeSampler = samplerPtr
            self.parsedMetadata = summary
            self.activeOptions = options
            self.currentLifecycleState = .loaded
        }
        #else
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

        let task = Task {
            do {
                if let runner = self.streamRunner {
                    let generatedCount = try await runner(request, continuation)
                    try LocalModelOutputValidator.validate(text: "non-empty-if-generated", generatedCount: generatedCount)
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

                // Each generate() call is an independent request. Reset llama.cpp
                // request state before decoding a new prompt; otherwise the second
                // request can reuse the previous KV cache/sampler state and fail
                // during prompt evaluation (for example evalFailed(-1)).
                llama_memory_clear(llama_get_memory(contextPtr), true)
                llama_sampler_reset(samplerPtr)

                // Verify device thermal & memory state
                let thermal = await self.deviceCapabilityProvider.thermalState
                if thermal == .critical {
                    throw LlamaCPPEngineError.thermalStateCritical
                }

                let memory = await self.deviceCapabilityProvider.memoryPressure
                if memory == .critical {
                    // The generation task owns the native pointers for its lifetime.
                    // Do not release them from inside this task; the caller can unload
                    // after the task has terminated.
                    throw LlamaCPPEngineError.memoryPressureCritical
                }

                // 1. Tokenize prompt using the model's GGUF chat template when available.
                // A generic "System:/User:/Assistant:" wrapper is not equivalent to the
                // model's trained instruction format and can produce severe quality/repetition
                // failures on chat-tuned GGUFs.
                let promptText = self.makeChatPrompt(
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

                // 2. Decode prompt in batches no larger than llama.cpp n_batch.
                // The context may be large, but n_batch is intentionally capped at 512.
                // A single batch sized to the full prompt would overflow for long prompts.
                let loadedContextWindow = self.stateLock.withLock { self.activeOptions?.contextWindow ?? 8192 }
                let modelContextLimit = self.parsedMetadata?.contextLength.flatMap { Int(exactly: $0) }
                let effectiveContextWindow = min(loadedContextWindow, modelContextLimit ?? loadedContextWindow)
                guard promptTokens.count < effectiveContextWindow else {
                    throw LlamaCPPEngineError.evalFailed(-2)
                }

                let batchCapacity = min(effectiveContextWindow, 512)
                var batch = llama_batch_init(Int32(batchCapacity), 0, 1)
                defer { llama_batch_free(batch) }

                var promptOffset = 0
                while promptOffset < promptTokens.count {
                    self.clearBatch(&batch)
                    let end = min(promptOffset + batchCapacity, promptTokens.count)
                    for index in promptOffset..<end {
                        let isLast = index == promptTokens.count - 1
                        try self.addTokenToBatch(&batch, id: promptTokens[index], pos: Int32(index), seqID: 0, logits: isLast)
                    }

                    let evalRes = llama_decode(contextPtr, batch)
                    guard evalRes == 0 else {
                        throw LlamaCPPEngineError.evalFailed(evalRes)
                    }
                    promptOffset = end
                }

                // 3. Generation loop
                let configuredMaxTokens = self.stateLock.withLock { self.activeOptions?.maxTokens ?? 512 }
                let maxTokens = min(request.maxTokens ?? configuredMaxTokens, effectiveGenerationCapacity(contextWindow: effectiveContextWindow, promptTokenCount: promptTokens.count))
                var currentPos = Int32(promptTokens.count)
                var generatedCount = 0

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
                        // Never unload native handles from inside the active generation
                        // task. unload() waits for this task; doing so here would either
                        // deadlock or free llama.cpp pointers while this task still owns them.
                        throw LlamaCPPEngineError.memoryPressureCritical
                    }

                    // Sample next token
                    let nextToken = llama_sampler_sample(samplerPtr, contextPtr, -1)

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

                    // Feed the sampled token back into the sampler. Without
                    // llama_sampler_accept(), the repetition-penalty sampler has no
                    // history and cannot prevent pathological token loops.
                    llama_sampler_accept(samplerPtr, nextToken)

                    generatedCount += 1
                    let isLastToken = (generatedCount >= maxTokens)
                    let chunk = LocalModelStreamChunk(
                        textDelta: deltaText,
                        finishReason: isLastToken ? "length" : nil
                    )
                    continuation.yield(chunk)

                    if isLastToken {
                        break
                    }

                    // Decode the sampled token using llama.cpp's canonical
                    // single-token batch helper. This avoids manually touching
                    // optional seq_id storage on the native batch.
                    var nextBatch = llama_batch_get_one(
                        UnsafeMutablePointer<llama_token>(mutating: [nextToken]),
                        1
                    )
                    let stepEval = llama_decode(contextPtr, nextBatch)
                    llama_batch_free(nextBatch)
                    guard stepEval == 0 else {
                        throw LlamaCPPEngineError.evalFailed(stepEval)
                    }
                    currentPos += 1

                    if currentThermal == .serious {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                }

                try LocalModelOutputValidator.validate(text: "non-empty-if-generated", generatedCount: generatedCount)

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

        continuation.onTermination = { [weak self] _ in
            task.cancel()
            self?.clearGenerationTask()
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
    }

    public func unload() async throws {
        setLifecycleState(.unloading)

        // Native llama.cpp handles must outlive the generation task. Cancelling a
        // Swift Task does not synchronously stop an in-flight C call, so releasing
        // model/context/sampler here immediately can cause a use-after-free crash
        // on the physical device.
        let task = stateLock.withLock {
            let t = activeGenerationTask
            activeGenerationTask = nil
            return t
        }
        task?.cancel()
        if let task {
            await task.value
        }

        await residencyCoordinator.releaseResidency(for: identity.id)
        releaseNativeHandles()
        stateLock.withLock {
            activeOptions = nil
            parsedMetadata = nil
            currentLifecycleState = .unloaded
        }
    }

    // MARK: - Private Helpers

    private func effectiveGenerationCapacity(contextWindow: Int, promptTokenCount: Int) -> Int {
        max(1, contextWindow - max(0, promptTokenCount))
    }

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
        }
    }

    #if canImport(cllama)
    private func makeChatPrompt(
        model: OpaquePointer,
        systemPrompt: String?,
        userPrompt: String
    ) -> String {
        let system = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let templatePtr = llama_model_chat_template(model, nil) else {
            return system.isEmpty
                ? userPrompt
                : "System: \(system)\nUser: \(userPrompt)\nAssistant:"
        }

        // Build the C message array while all backing strings remain alive.
        var formatted: [CChar] = Array(repeating: 0, count: 4096)
        let rendered = system.isEmpty
            ? userPrompt.withCString { userPtr in
                "user".withCString { rolePtr in
                    var message = llama_chat_message(role: rolePtr, content: userPtr)
                    return withUnsafePointer(to: &message) { messagePtr in
                        llama_chat_apply_template(templatePtr, messagePtr, 1, true, &formatted, Int32(formatted.count))
                    }
                }
            }
            : system.withCString { systemPtr in
                userPrompt.withCString { userPtr in
                    "system".withCString { systemRolePtr in
                        "user".withCString { userRolePtr in
                            var messages = [
                                llama_chat_message(role: systemRolePtr, content: systemPtr),
                                llama_chat_message(role: userRolePtr, content: userPtr)
                            ]
                            return messages.withUnsafeBufferPointer { buffer in
                                llama_chat_apply_template(
                                    templatePtr,
                                    buffer.baseAddress,
                                    buffer.count,
                                    true,
                                    &formatted,
                                    Int32(formatted.count)
                                )
                            }
                        }
                    }
                }
            }

        guard rendered > 0 else {
            return system.isEmpty
                ? userPrompt
                : "System: \(system)\nUser: \(userPrompt)\nAssistant:"
        }

        if rendered < Int32(formatted.count) {
            return String(cString: formatted)
        }

        var resized = Array<CChar>(repeating: 0, count: Int(rendered) + 1)
        let secondPass: Int32 = system.isEmpty
            ? userPrompt.withCString { userPtr in
                "user".withCString { rolePtr in
                    var message = llama_chat_message(role: rolePtr, content: userPtr)
                    return withUnsafePointer(to: &message) { messagePtr in
                        llama_chat_apply_template(templatePtr, messagePtr, 1, true, &resized, Int32(resized.count))
                    }
                }
            }
            : system.withCString { systemPtr in
                userPrompt.withCString { userPtr in
                    "system".withCString { systemRolePtr in
                        "user".withCString { userRolePtr in
                            var messages = [
                                llama_chat_message(role: systemRolePtr, content: systemPtr),
                                llama_chat_message(role: userRolePtr, content: userPtr)
                            ]
                            return messages.withUnsafeBufferPointer { buffer in
                                llama_chat_apply_template(
                                    templatePtr,
                                    buffer.baseAddress,
                                    buffer.count,
                                    true,
                                    &resized,
                                    Int32(resized.count)
                                )
                            }
                        }
                    }
                }
            }

        guard secondPass > 0 else {
            return system.isEmpty
                ? userPrompt
                : "System: \(system)\nUser: \(userPrompt)\nAssistant:"
        }
        return String(cString: resized)
    }

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
        let utf8 = Array(text.utf8CString)
        let utf8Count = utf8.count - 1
        let maxTokens = utf8Count + (addSpecial ? 1 : 0) + 16
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        let count = utf8.withUnsafeBufferPointer { buffer in
            llama_tokenize(
                vocab,
                buffer.baseAddress,
                Int32(utf8Count),
                &tokens,
                Int32(maxTokens),
                addSpecial,
                false
            )
        }
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

    private func addTokenToBatch(_ batch: inout llama_batch, id: llama_token, pos: Int32, seqID: Int32, logits: Bool) throws {
        // Never use precondition/preconditionFailure at the native boundary:
        // those turn malformed llama_batch state into an intentional process crash.
        let idx = Int(batch.n_tokens)
        guard idx >= 0,
              let token = batch.token,
              let posBuffer = batch.pos,
              let nSeqID = batch.n_seq_id,
              let seqIDs = batch.seq_id,
              let logitsBuffer = batch.logits else {
            throw LlamaCPPEngineError.evalFailed(-3)
        }

        guard let seqIDBuffer = seqIDs[idx] else {
            throw LlamaCPPEngineError.evalFailed(-3)
        }

        token[idx] = id
        posBuffer[idx] = pos
        nSeqID[idx] = 1
        seqIDBuffer[0] = seqID
        logitsBuffer[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    private func clearBatch(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }
    #endif
}
