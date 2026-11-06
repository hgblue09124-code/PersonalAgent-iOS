import Foundation
import PAKernel
import PAProviders
#if canImport(PAProvidersGoogleLiteRT)
import PAProvidersGoogleLiteRT
#endif

/// Selects a concrete local inference engine inside the local-provider boundary.
/// Composition depends on this factory rather than importing individual engines.
public enum LocalModelEngineFactory {
    public static func make(
        identity: LocalModelIdentity,
        deviceCapabilityProvider: any DeviceCapabilityProviding
    ) throws -> any LocalModelEngine {
        if identity.localURL?.pathExtension.lowercased() == "litertlm" {
            #if canImport(PAProvidersGoogleLiteRT)
            return GoogleLiteRTModelEngine(identity: identity)
            #else
            throw ProviderRuntimeError.unavailable
            #endif
        }

        return LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceCapabilityProvider
        )
    }
}
