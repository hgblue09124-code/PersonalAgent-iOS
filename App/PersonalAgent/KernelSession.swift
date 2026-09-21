import Foundation
import SwiftUI
import PAKernel
import PAComposition
import PAArchitecture
import PAProviders

@MainActor
final class KernelSession: ObservableObject {
    let composition: M8CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?
    @Published var providerID: String
    @Published var providerLifecycle: String
    @Published var moduleIDs: [String]
    @Published var localModels: [LocalModelDescriptor] = []
    @Published var activeModelDescriptor: LocalModelDescriptor? = nil

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.moduleIDs = []
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
        moduleIDs = await composition.registeredModuleIDs()
        localModels = (try? await composition.modelStorage.listModels()) ?? []
        activeModelDescriptor = try? await composition.modelStorage.getActiveModelDescriptor()
    }

    func start() async { await run { try await composition.session.start() } }
    func pause() async { await run { try await composition.session.pause() } }
    func resume() async { await run { try await composition.session.resume() } }
    func stop() async { await run { try await composition.session.stop() } }

    func submitGoal(_ statement: String) async {
        await run {
            _ = try await composition.session.submitInput(statement)
        }
    }

    func importGGUFModel(from url: URL, name: String? = nil) async throws {
        _ = try await composition.modelStorage.importModel(from: url, name: name)
        await refresh()
    }

    func selectActiveLocalModel(id: ModelID?) async throws {
        try await composition.modelStorage.selectActiveModel(id: id)
        await refresh()
    }

    func deleteLocalModel(id: ModelID) async throws {
        try await composition.modelStorage.deleteModel(id: id)
        await refresh()
    }

    func activeLocalModelEngine() async throws -> (any LocalModelEngine)? {
        try await composition.activeLocalModelEngine()
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        await refresh()
    }
}
