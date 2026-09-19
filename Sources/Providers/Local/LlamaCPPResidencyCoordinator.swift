import Foundation
import PAFoundation
import PAProviders

/// Actor enforcing the invariant that at most one model weight stack is resident in memory at any given time.
public actor LlamaCPPResidencyCoordinator {
    public static let shared = LlamaCPPResidencyCoordinator()

    private var currentResidentID: ModelID?
    private var currentEngine: (any LocalModelEngine)?

    public init() {}

    /// Registers an engine as resident. If another engine is currently resident, unloads it first to enforce exclusivity.
    public func requestResidency(for engine: any LocalModelEngine) async throws {
        let requestedID = engine.identity.id
        if let currentEngine = self.currentEngine, let currentID = self.currentResidentID, currentID != requestedID {
            // Unload the existing resident engine before permitting the target model to load
            try await currentEngine.unload()
            self.currentEngine = nil
            self.currentResidentID = nil
        }
        self.currentResidentID = requestedID
        self.currentEngine = engine
    }

    /// Unregisters an engine from residency.
    public func releaseResidency(for modelID: ModelID) {
        if currentResidentID == modelID {
            self.currentResidentID = nil
            self.currentEngine = nil
        }
    }

    public var residentModelID: ModelID? {
        currentResidentID
    }

    public var isResident: Bool {
        currentResidentID != nil
    }
}
