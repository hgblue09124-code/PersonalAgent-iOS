import Foundation
import Testing
import PAKernel
import PAProviders
@testable import PAProvidersRemote

@Suite("Incremental OpenAI-compatible SSE decoding")
struct ChatCompletionsStreamingTests {
    private func sse(_ object: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: object)
        return Data("data: ".utf8) + json + Data([0x0A])
    }

    @Test func emitsDeltaBeforeTerminalMarkerArrives() throws {
        var decoder = ChatCompletionsStreamDecoder()
        let first = Data(#"data: {"model":"model-x","choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#.utf8)
        #expect(try decoder.append(first + Data([0x0A])) == [.delta("hello")])
        #expect(try decoder.append(Data("data: [DONE]\n".utf8)).isEmpty)
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

    @Test func assemblesFragmentedToolNameAndArguments() throws {
        var decoder = ChatCompletionsStreamDecoder()
        let first = try sse(["choices": [["delta": ["tool_calls": [
            ["index": 0, "id": "call_1", "type": "function",
             "function": ["name": "workspace.", "arguments": "{\"path\":"]]
        ]], "finish_reason": NSNull()]]])
        let second = try sse(["choices": [["delta": ["tool_calls": [
            ["index": 0, "function": [
                "name": "create_file",
                "arguments": "\"a.txt\",\"content\":\"hello\"}"
            ]]
        ]], "finish_reason": "tool_calls"]]])
        #expect(try decoder.append(first).isEmpty)
        #expect(try decoder.append(second).isEmpty)
        _ = try decoder.append(Data("data: [DONE]\n".utf8))
        let events = try decoder.finish()
        #expect(events.contains(.toolCall(
            name: "workspace.create_file",
            argumentsJSON: #"{"path":"a.txt","content":"hello"}"#
        )))
        guard case .completed(let response)? = events.last else {
            Issue.record("expected completion after tool call")
            return
        }
        #expect(response.text.isEmpty)
        #expect(response.finishReason == "tool_calls")
    }

    @Test func rejectsMalformedToolCallArguments() throws {
        var decoder = ChatCompletionsStreamDecoder()
        let data = try sse(["choices": [["delta": ["tool_calls": [
            ["index": 0, "function": ["name": "run", "arguments": "not-json"]]
        ]], "finish_reason": "tool_calls"]]])
        _ = try decoder.append(data)
        _ = try decoder.append(Data("data: [DONE]\n".utf8))
        #expect(throws: ProviderRuntimeError.decodingFailure) { _ = try decoder.finish() }
    }

    @Test func rejectsTruncatedStreamWithoutDoneMarker() throws {
        var decoder = ChatCompletionsStreamDecoder()
        _ = try decoder.append(Data(#"data: {"choices":[{"delta":{"content":"partial"}}]}"#.utf8) + Data([0x0A]))
        #expect(throws: ProviderRuntimeError.decodingFailure) { _ = try decoder.finish() }
    }
}
