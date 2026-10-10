import Foundation
import PAKernel
import PAProviders

/// Maps the semantic contract onto the OpenAI-compatible chat.completions wire format.
/// Used by Grok, OpenAI, OpenAI-compatible, and local HTTP adapters.
/// This type is an adapter helper. It is not a Kernel type.
public enum ChatCompletionsCodec: Sendable {
    /// Require TLS for network endpoints. Cleartext HTTP is permitted only for loopback
    /// development servers so provider credentials and prompts cannot cross a LAN in plaintext.
    public static func validateEndpointURL(_ endpointURL: String) throws -> URL {
        guard let components = URLComponents(string: endpointURL),
              let scheme = components.scheme?.lowercased(),
              let rawHost = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            throw ProviderRuntimeError.invalidConfiguration
        }

        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        return url
    }

    public static func encodeRequest(
        _ request: LLMRequest,
        endpointURL: String,
        authorizationHeader: String?,
        stream: Bool
    ) throws -> ProviderTransportRequest {
        let url = try validateEndpointURL(endpointURL)
        var body: [String: Any] = [
            "model": request.model.rawValue,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": stream,
        ]
        if let temperature = request.parameters.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = request.parameters.maxOutputTokens {
            body["max_tokens"] = maxTokens
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        var headers = [
            "Content-Type": "application/json",
            "Accept": stream ? "text/event-stream" : "application/json",
        ]
        if let authorizationHeader, !authorizationHeader.isEmpty {
            headers["Authorization"] = authorizationHeader
        }
        return ProviderTransportRequest(
            url: endpointURL,
            method: "POST",
            headers: headers,
            body: data
        )
    }

    public static func decodeResponse(_ response: ProviderTransportResponse) throws -> LLMResponse {
        if response.statusCode == 200 {
            return try decodeSuccess(body: response.body)
        }
        throw ProviderRuntimeError.from(statusCode: response.statusCode)
    }

    public static func decodeSuccess(body: Data) throws -> LLMResponse {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: body)
        } catch {
            throw ProviderRuntimeError.decodingFailure
        }
        guard let json = object as? [String: Any] else {
            throw ProviderRuntimeError.decodingFailure
        }
        let model = (json["model"] as? String).map(ModelID.init(rawValue:))
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            throw ProviderRuntimeError.decodingFailure
        }
        let finish = (first["finish_reason"] as? String) ?? "stop"
        if let message = first["message"] as? [String: Any], let text = message["content"] as? String {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderRuntimeError.decodingFailure
            }
            return LLMResponse(text: text, finishReason: finish, model: model)
        }
        if let text = first["text"] as? String {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderRuntimeError.decodingFailure
            }
            return LLMResponse(text: text, finishReason: finish, model: model)
        }
        throw ProviderRuntimeError.decodingFailure
    }

    public static func decodeStreamEvents(_ body: Data) throws -> [LLMStreamEvent] {
        var decoder = ChatCompletionsStreamDecoder()
        let deltas = try decoder.append(body)
        return deltas + (try decoder.finish())
    }
}

/// Incremental Server-Sent Events decoder. Buffers incomplete lines, not the full response.
public struct ChatCompletionsStreamDecoder: Sendable {
    private var pending = Data()
    private var fullText = ""
    private var finishReason = "stop"
    private var model: ModelID?
    private var sawTerminalMarker = false

    public init() {}

    public mutating func append(_ chunk: Data) throws -> [LLMStreamEvent] {
        pending.append(chunk)
        var events: [LLMStreamEvent] = []
        let newline = Data([0x0A])
        while let range = pending.range(of: newline) {
            let line = Data(pending[..<range.lowerBound])
            pending.removeSubrange(pending.startIndex..<range.upperBound)
            try consume(line, into: &events)
        }
        return events
    }

    public mutating func finish() throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        if !pending.isEmpty {
            try consume(pending, into: &events)
            pending.removeAll(keepingCapacity: false)
        }
        guard sawTerminalMarker,
              !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderRuntimeError.decodingFailure
        }
        events.append(.completed(LLMResponse(text: fullText, finishReason: finishReason, model: model)))
        return events
    }

    private mutating func consume(_ rawLine: Data, into events: inout [LLMStreamEvent]) throws {
        var lineData = rawLine
        if lineData.last == 0x0D { lineData.removeLast() }
        guard let line = String(data: lineData, encoding: .utf8) else {
            throw ProviderRuntimeError.decodingFailure
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return }
        if payload == "[DONE]" {
            sawTerminalMarker = true
            return
        }
        guard !sawTerminalMarker else { return }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderRuntimeError.decodingFailure
        }
        if let modelName = object["model"] as? String {
            model = ModelID(rawValue: modelName)
        }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
            return
        }
        if let reason = first["finish_reason"] as? String {
            finishReason = reason
        }
        guard let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else { return }
        fullText += content
        events.append(.delta(content))
    }
}
