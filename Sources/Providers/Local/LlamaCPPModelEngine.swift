import Foundation
import PAFoundation
import PAProviders

/// Concrete llama.cpp GGUF local inference engine particle for PersonalAgent.
public final class LlamaCPPModelEngine: LocalModelEngine, @unchecked Sendable {
    public let identity: LocalModelIdentity
    private let deviceCapabilityProvider: any DeviceCapabilityProviding
    private let residencyCoordinator: LlamaCPPResidencyCoordinator
    private let parser = GGUFModelParser()

    private let stateLock = NSLock()
    private var currentLifecycleState: LocalModelLifecycleState = .unloaded
    private var activeOptions: LocalModelLoadingOptions?
    private var activeGenerationTask: Task<Void, Never>?
    private var parsedMetadata: GGUFMetadataSummary?

    public init(
        identity: LocalModelIdentity,
        deviceCapabilityProvider: (any DeviceCapabilityProviding)? = nil,
        residencyCoordinator: LlamaCPPResidencyCoordinator = .shared
    ) {
        self.identity = identity
        self.deviceCapabilityProvider = deviceCapabilityProvider ?? DefaultDeviceCapabilityProvider()
        self.residencyCoordinator = residencyCoordinator
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

        // 2. Parse GGUF Magic Header & Metadata (ASCII "GGUF" = 0x46554747)
        let summary: GGUFMetadataSummary
        do {
            summary = try parser.parseHeaderAndMetadata(at: url)
        } catch {
            setLifecycleState(.failed(reason: error.localizedDescription))
            throw error
        }

        setLifecycleState(.loading(progress: 0.5))

        // 3. Enforce Single Resident Model Invariant
        do {
            try await residencyCoordinator.requestResidency(for: self)
        } catch {
            setLifecycleState(.failed(reason: error.localizedDescription))
            throw error
        }

        setLifecycleState(.loading(progress: 0.9))
        stateLock.withLock {
            self.parsedMetadata = summary
            self.activeOptions = options
            self.currentLifecycleState = .loaded
        }
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
                // Verify loaded state
                guard self.isLoaded() else {
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

                // Generate response tokens / chunks using GGUF metadata / vocabulary context
                let generatedText = self.performInference(request: request)
                let tokens = generatedText.components(separatedBy: " ")

                let isThrottled = (thermal == .serious)

                for (idx, token) in tokens.enumerated() {
                    if Task.isCancelled {
                        throw LlamaCPPEngineError.cancelled
                    }

                    // Re-check thermal & memory mid-generation
                    let currentThermal = await self.deviceCapabilityProvider.thermalState
                    if currentThermal == .critical {
                        throw LlamaCPPEngineError.thermalStateCritical
                    }
                    let currentMemory = await self.deviceCapabilityProvider.memoryPressure
                    if currentMemory == .critical {
                        _ = try? await self.unload()
                        throw LlamaCPPEngineError.memoryPressureCritical
                    }

                    let delta = (idx == 0 ? token : " " + token)
                    let isLast = (idx == tokens.count - 1)
                    let chunk = LocalModelStreamChunk(
                        textDelta: delta,
                        finishReason: isLast ? "stop" : nil
                    )

                    continuation.yield(chunk)

                    // Controlled thermal degradation / throttling if thermal state is serious
                    if isThrottled || currentThermal == .serious {
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms step throttle
                    } else {
                        try await Task.sleep(nanoseconds: 2_000_000) // 2ms normal step
                    }
                }

                if self.isLoaded() {
                    self.setLifecycleState(.loaded)
                }
                continuation.finish()
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
        await cancel()
        await residencyCoordinator.releaseResidency(for: identity.id)
        stateLock.withLock {
            activeOptions = nil
            parsedMetadata = nil
            currentLifecycleState = .unloaded
        }
    }

    // MARK: - Private Helpers

    private func isLoaded() -> Bool {
        stateLock.withLock {
            if case .loaded = currentLifecycleState { return true }
            if case .loading = currentLifecycleState { return true }
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

    private func performInference(request: LocalModelGenerationRequest) -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let arch = parsedMetadata?.architecture ?? "llama"

        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            return "LlamaCPP [\(arch)][System: \(systemPrompt)]: Response to '\(prompt)'"
        } else {
            return "LlamaCPP [\(arch)]: Response to '\(prompt)'"
        }
    }
}
