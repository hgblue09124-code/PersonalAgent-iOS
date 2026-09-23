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

    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelID: ModelID?
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineState: LocalModelLifecycleState

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.moduleIDs = []
        self.installedModels = []
        self.activeModelID = nil
        self.activeModelDescriptor = nil
        self.activeEngineState = .unloaded
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
        moduleIDs = await composition.registeredModuleIDs()

        let storage = composition.localModelStorage
        installedModels = (try? await storage.listModels()) ?? []
        activeModelID = try? await storage.activeModelID()
        activeModelDescriptor = try? await storage.activeModelDescriptor()

        if let engine = try? await composition.activeLocalModelEngine() {
            activeEngineState = await engine.lifecycleState
        } else {
            activeEngineState = .unloaded
        }
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

    func importModel(from url: URL, name: String? = nil) async {
        await run {
            _ = try await composition.localModelStorage.importModel(from: url, name: name)
        }
    }

    func selectActiveModel(id: ModelID?) async {
        await run {
            try await composition.setActiveLocalModel(id: id)
        }
    }

    func loadActiveModel(options: LocalModelLoadingOptions? = nil) async {
        await run {
            _ = try await composition.loadActiveLocalModel(options: options)
        }
    }

    func unloadActiveModel() async {
        await run {
            try await composition.unloadActiveLocalModel()
        }
    }

    func deleteModel(id: ModelID) async {
        await run {
            try await composition.deleteLocalModel(id: id)
        }
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
