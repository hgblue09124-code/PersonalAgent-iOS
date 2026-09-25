import Foundation

public enum ProviderRuntimeError: Error, Sendable, Equatable {
    case unavailable
    case contextLimitExceeded
    case unsupportedCapability(String)
    case transport(String)
    case decoding(String)
    case invalidConfiguration
    case authenticationFailure
    case authorizationFailure
    case rateLimited
    case networkFailure
    case timeout
    case invalidRequest
    case providerFailure
    case decodingFailure
    case cancelled
    case unknown
}

extension ProviderRuntimeError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unavailable: return "unavailable"
        case .contextLimitExceeded: return "contextLimitExceeded"
        case .unsupportedCapability(let name): return "unsupportedCapability:\(name)"
        case .transport: return "transport"
        case .decoding: return "decoding"
        case .invalidConfiguration: return "invalidConfiguration"
        case .authenticationFailure: return "authenticationFailure"
        case .authorizationFailure: return "authorizationFailure"
        case .rateLimited: return "rateLimited"
        case .networkFailure: return "networkFailure"
        case .timeout: return "timeout"
        case .invalidRequest: return "invalidRequest"
        case .providerFailure: return "providerFailure"
        case .decodingFailure: return "decodingFailure"
        case .cancelled: return "cancelled"
        case .unknown: return "unknown"
        }
    }
}

extension ProviderRuntimeError {
    /// Automatic retries are deferred. This only classifies a failure.
    public var retryClassification: RetryClassification {
        switch self {
        case .rateLimited, .networkFailure, .timeout, .transport, .providerFailure:
            return .retryableTransient
        case .unavailable,
             .contextLimitExceeded,
             .unsupportedCapability,
             .decoding,
             .invalidConfiguration,
             .authenticationFailure,
             .authorizationFailure,
             .invalidRequest,
             .decodingFailure,
             .cancelled,
             .unknown:
            return .doNotRetry
        }
    }

    public static func from(statusCode: Int) -> ProviderRuntimeError {
        switch statusCode {
        case 400: return .invalidRequest
        case 401: return .authenticationFailure
        case 403: return .authorizationFailure
        case 408: return .timeout
        case 429: return .rateLimited
        case 499: return .cancelled
        case 500...599: return .providerFailure
        default: return .networkFailure
        }
    }
}


extension ProviderRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Provider unavailable."
        case .contextLimitExceeded: return "Provider context limit exceeded."
        case .unsupportedCapability(let name): return "Unsupported provider capability: \(name)."
        case .transport(let message): return "Provider transport error: \(message)"
        case .decoding(let message): return "Provider decoding error: \(message)"
        case .invalidConfiguration: return "Provider configuration is invalid."
        case .authenticationFailure: return "Provider authentication failed. Check the API key."
        case .authorizationFailure: return "Provider authorization failed for this account/model."
        case .rateLimited: return "Provider rate limit reached."
        case .networkFailure: return "Could not reach the provider."
        case .timeout: return "Provider request timed out."
        case .invalidRequest: return "Provider rejected the request (HTTP 400)."
        case .providerFailure: return "Provider returned a server error."
        case .decodingFailure: return "Provider returned an unsupported or malformed response."
        case .cancelled: return "Provider request was cancelled."
        case .unknown: return "Unknown provider error."
        }
    }
}
