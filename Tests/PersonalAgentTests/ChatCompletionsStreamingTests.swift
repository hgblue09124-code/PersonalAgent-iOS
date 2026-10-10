import Foundation
import Testing
import PAKernel
import PAProviders
@testable import PAProvidersRemote

@Suite("Incremental OpenAI-compatible SSE decoding")
struct ChatCompletionsStreamingTests {
    @Test func emitsDeltaBeforeTerminalMarkerArrives() throws {
        var decoder = ChatCompletionsStreamDecoder()
        let first = Data(#"data: {"model":"model-x","choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#.utf8)
        let firstEvents = try decoder.append(first + Data([0x0A]))
        #expect(firstEvents == [.delta("hello")])

        let terminalEvents = try decoder.append(Data("data: [DONE]\n".utf8))
        #expect(terminalEvents.isEmpty)
        guard case .completed(let response)? = try decoder.finish().last else {
            Issue.record("expected terminal completion event")
            return
        }
        #expect(response.text == "hello")
        #expect(response.model == ModelID(rawValue: "model-x"))
    }

    @Test func buffersPartialSSELineAcrossChunks() throws {
        var decoder = ChatCompletionsStreamDecoder()
        let partial = Data(#"data: {"choices":[{"delta":{"content":"hel"#.utf8)
        #expect(try decoder.append(partial).isEmpty)
        let remainder = Data(#"lo"},"finish_reason":null}]}"#.utf8) + Data([0x0A])
        #expect(try decoder.append(remainder) == [.delta("hello")])
        _ = try decoder.append(Data("data: [DONE]\n".utf8))
        guard case .completed(let response)? = try decoder.finish().last else {
            Issue.record("expected terminal completion event")
            return
        }
        #expect(response.text == "hello")
    }

    @Test func rejectsTruncatedStreamWithoutDoneMarker() throws {
        var decoder = ChatCompletionsStreamDecoder()
        _ = try decoder.append(Data(#"data: {"choices":[{"delta":{"content":"partial"}}]}"#.utf8) + Data([0x0A]))
        #expect(throws: ProviderRuntimeError.decodingFailure) {
            _ = try decoder.finish()
        }
    }
}
