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
        let raw = String(data: body, encoding: .utf8) ?? ""
        var deltas: [String] = []
        var finish = "stop"
        var model: ModelID?
        var sawTerminalMarker = false
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                sawTerminalMarker = true
                continue
            }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw ProviderRuntimeError.decodingFailure
            }
            if let modelName = object["model"] as? String {
                model = ModelID(rawValue: modelName)
            }
            guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
                continue
            }
            if let reason = first["finish_reason"] as? String {
                finish = reason
            }
            if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
                deltas.append(content)
            }
        }
        let fullText = deltas.joined()
        guard sawTerminalMarker else {
            throw ProviderRuntimeError.decodingFailure
        }
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderRuntimeError.decodingFailure
        }
        var events: [LLMStreamEvent] = deltas.map { .delta($0) }
        events.append(.completed(LLMResponse(text: fullText, finishReason: finish, model: model)))
        return events
    }
}
