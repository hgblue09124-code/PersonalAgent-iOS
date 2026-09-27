import Foundation
import PAKernel

public actor LlamaCPPResidencyCoordinator {
    public static let shared = LlamaCPPResidencyCoordinator()

    private(set) public var residentModelID: ModelID?
    private weak var residentEngine: LlamaCPPModelEngine?

    public init() {}

    public func requestResidency(for engine: LlamaCPPModelEngine) async throws {
        if let currentEngine = residentEngine, currentEngine !== engine {
            try await currentEngine.unload()
        }
        residentEngine = engine
        residentModelID = engine.identity.id
    }

    public func releaseResidency(for modelID: ModelID) {
        if residentModelID == modelID {
            residentModelID = nil
            residentEngine = nil
        }
    }
}
