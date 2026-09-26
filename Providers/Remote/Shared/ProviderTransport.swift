import Foundation
import PASecurity

/// Byte-level transport. Semantic providers must not expose this type to Kernel callers.
public struct ProviderTransportRequest: Sendable, Equatable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        url: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public var redactedHeaders: [String: String] {
        var copy = headers
        for key in copy.keys where Self.sensitiveHeaderKeys.contains(key.lowercased()) {
            copy[key] = "<redacted>"
        }
        return copy
    }

    public static let sensitiveHeaderKeys: Set<String> = [
        "authorization",
        "x-api-key",
        "api-key",
        "proxy-authorization",
    ]
}

public struct ProviderTransportResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol ProviderTransport: Sendable {
    func send(_ request: ProviderTransportRequest) async throws -> ProviderTransportResponse
}

/// Bridges the existing PASecurity network port without leaking URLSession.
public struct SecurityNetworkTransport: ProviderTransport {
    private let network: any NetworkAccess

    public init(network: any NetworkAccess) {
        self.network = network
    }

    public func send(_ request: ProviderTransportRequest) async throws -> ProviderTransportResponse {
        let response = try await network.data(
            for: NetworkRequest(
                url: request.url,
                method: request.method,
                headers: request.headers,
                body: request.body
            )
        )
        return ProviderTransportResponse(statusCode: response.statusCode, body: response.body)
    }
}

public struct UnavailableTransport: ProviderTransport {
    public init() {}

    public func send(_ request: ProviderTransportRequest) async throws -> ProviderTransportResponse {
        throw ProviderRuntimeError.invalidConfiguration
    }
}

/// Deterministic transport for adapter fixture tests. Never touches the network.
public actor ScriptedTransport: ProviderTransport {
    public enum Script: Sendable {
        case response(ProviderTransportResponse)
        case fail(ProviderRuntimeError)
        case hang
    }

    private var scripts: [Script]
    private var recorded: [ProviderTransportRequest] = []

    public init(scripts: [Script]) {
        self.scripts = scripts
    }

    public func recordedRequests() -> [ProviderTransportRequest] {
        recorded
    }

    public func send(_ request: ProviderTransportRequest) async throws -> ProviderTransportResponse {
        recorded.append(request)
        guard !scripts.isEmpty else {
            throw ProviderRuntimeError.unknown
        }
        let script = scripts.removeFirst()
        switch script {
        case .response(let response):
            return response
        case .fail(let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw ProviderRuntimeError.timeout
        }
    }
}
