with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_mock = """    private actor ObservableMockEngine: LocalModelEngine {
        let identity: LocalModelIdentity
        var state: LocalModelLifecycleState
        var shouldFailUnload: Bool
        var shouldFailGenerate: Bool

        private(set) var completeCallCount = 0
        private(set) var streamCallCount = 0
        private(set) var unloadCallCount = 0
        private(set) var lastGenerationRequest: LocalModelGenerationRequest?

        init(
            identity: LocalModelIdentity,
            state: LocalModelLifecycleState = .loaded,
            shouldFailUnload: Bool = false,
            shouldFailGenerate: Bool = false
        ) {
            self.identity = identity
            self.state = state
            self.shouldFailUnload = shouldFailUnload
            self.shouldFailGenerate = shouldFailGenerate
        }

        var availability: LocalModelAvailability { .ready }
        var lifecycleState: LocalModelLifecycleState { state }

        func load(options: LocalModelLoadingOptions) async throws {
            state = .loaded
        }

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            completeCallCount += 1
            lastGenerationRequest = request
            if shouldFailGenerate || state != .loaded {
                throw LlamaCPPEngineError.modelNotLoaded
            }
            return LocalModelResponse(text: "Observable mock output for: \\(request.prompt)")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            streamCallCount += 1
            lastGenerationRequest = request
            let isLoaded = (state == .loaded)
            let failGen = shouldFailGenerate
            return AsyncThrowingStream { continuation in
                if failGen || !isLoaded {
                    continuation.finish(throwing: LlamaCPPEngineError.modelNotLoaded)
                } else {
                    continuation.yield(LocalModelStreamChunk(textDelta: "Observable stream chunk", finishReason: "stop"))
                    continuation.finish()
                }
            }
        }

        func cancel() async {}

        func unload() async throws {
            unloadCallCount += 1
            if shouldFailUnload {
                throw LocalModelStorageError.storageCorrupt("Engine unload failed")
            }
            state = .unloaded
        }
    }"""

good_mock = """    private final class ObservableMockEngine: LocalModelEngine, @unchecked Sendable {
        let identity: LocalModelIdentity
        private var _state: LocalModelLifecycleState
        let shouldFailUnload: Bool
        let shouldFailGenerate: Bool

        private(set) var completeCallCount = 0
        private(set) var streamCallCount = 0
        private(set) var unloadCallCount = 0
        private(set) var lastGenerationRequest: LocalModelGenerationRequest?

        private let lock = NSLock()

        init(
            identity: LocalModelIdentity,
            state: LocalModelLifecycleState = .loaded,
            shouldFailUnload: Bool = false,
            shouldFailGenerate: Bool = false
        ) {
            self.identity = identity
            self._state = state
            self.shouldFailUnload = shouldFailUnload
            self.shouldFailGenerate = shouldFailGenerate
        }

        var availability: LocalModelAvailability { .ready }

        var lifecycleState: LocalModelLifecycleState {
            get async {
                lock.withLock { _state }
            }
        }

        func load(options: LocalModelLoadingOptions) async throws {
            lock.withLock { _state = .loaded }
        }

        func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
            lock.withLock {
                completeCallCount += 1
                lastGenerationRequest = request
            }
            if shouldFailGenerate || lock.withLock({ _state }) != .loaded {
                throw LlamaCPPEngineError.modelNotLoaded
            }
            return LocalModelResponse(text: "Observable mock output for: \\(request.prompt)")
        }

        func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
            lock.withLock {
                streamCallCount += 1
                lastGenerationRequest = request
            }
            let isLoaded = lock.withLock { _state } == .loaded
            let failGen = shouldFailGenerate
            return AsyncThrowingStream { continuation in
                if failGen || !isLoaded {
                    continuation.finish(throwing: LlamaCPPEngineError.modelNotLoaded)
                } else {
                    continuation.yield(LocalModelStreamChunk(textDelta: "Observable stream chunk", finishReason: "stop"))
                    continuation.finish()
                }
            }
        }

        func cancel() async {}

        func unload() async throws {
            lock.withLock { unloadCallCount += 1 }
            if shouldFailUnload {
                throw LocalModelStorageError.storageCorrupt("Engine unload failed")
            }
            lock.withLock { _state = .unloaded }
        }
    }"""

if bad_mock in content:
    updated = content.replace(bad_mock, good_mock)
    with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
        f.write(updated)
    print("Updated ObservableMockEngine to class with NSLock")
else:
    print("Error: bad_mock not found")
