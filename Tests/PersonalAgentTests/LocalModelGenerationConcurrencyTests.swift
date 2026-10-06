import Foundation
import Testing
import PAKernel
import PAProviders
import PAProvidersLocal

@Suite("Local Model Generation Concurrency Tests")
struct LocalModelGenerationConcurrencyTests {
    @Test func cancellationDoesNotReleaseGenerationLockBeforeTaskFinishes() async throws {
        let engine = LlamaCPPModelEngine(
            identity: LocalModelIdentity(
                id: ModelID(rawValue: "test-generation"),
                name: "Test Generation",
                contextTokenLimit: 2048
            ),
            streamRunner: { _, continuation in
                continuation.yield(LocalModelStreamChunk(textDelta: "partial"))
                try? await Task.sleep(for: .milliseconds(150))
                continuation.finish()
                return 1
            }
        )

        let first = engine.generateStream(
            request: LocalModelGenerationRequest(prompt: "first")
        )

        let consumer = Task {
            for try await _ in first { }
        }
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        _ = await consumer.result

        let second = engine.generateStream(
            request: LocalModelGenerationRequest(prompt: "second")
        )

        do {
            for try await _ in second {
                Issue.record("Second generation unexpectedly started while first task was still finishing.")
            }
            Issue.record("Second generation unexpectedly completed instead of failing with generationInProgress.")
        } catch {
            #expect(error as? LlamaCPPEngineError == .generationInProgress)
        }

        try await Task.sleep(for: .milliseconds(180))
    }
}
