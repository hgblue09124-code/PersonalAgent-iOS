import Foundation
import SwiftUI
import PAKernel
import PAComposition
import PAArchitecture
import PAProviders
import PAFoundation

@MainActor
final class KernelSession: ObservableObject {
    let composition: M8CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?
    @Published var providerID: String
    @Published var providerLifecycle: String
    @Published var moduleIDs: [String]

    // Local Model Management State
    @Published var installedModels: [LocalModelDescriptor]
    @Published var activeModelDescriptor: LocalModelDescriptor?
    @Published var activeEngineLifecycle: LocalModelLifecycleState
    private var activeEngine: (any LocalModelEngine)?

    init(composition: M8CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
        self.providerID = composition.selectedProviderID
        self.providerLifecycle = "unknown"
        self.moduleIDs = []
        self.installedModels = []
        self.activeModelDescriptor = nil
        self.activeEngineLifecycle = .unloaded
        self.activeEngine = nil
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
        moduleIDs = await composition.registeredModuleIDs()
        await refreshModels()
    }

    func refreshModels() async {
        do {
            installedModels = try await composition.localModelStorage.listModels()
            activeModelDescriptor = try await composition.localModelStorage.activeModelDescriptor()

            if activeModelDescriptor != nil {
                let engine = try await composition.activeLocalModelEngine()
                self.activeEngine = engine
                if let engine {
                    activeEngineLifecycle = await engine.lifecycleState
                } else {
                    activeEngineLifecycle = .unloaded
                }
            } else {
                activeEngine = nil
                activeEngineLifecycle = .unloaded
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    func importGGUF(from sourceURL: URL, name: String? = nil) async {
        await run {
            _ = try await composition.localModelStorage.importModel(from: sourceURL, name: name)
            await refreshModels()
        }
    }

    func selectActiveModel(id: ModelID?) async {
        await run {
            if let activeEngine {
                try? await activeEngine.unload()
            }
            try await composition.localModelStorage.setActiveModel(id: id)
            await refreshModels()
        }
    }

    func loadActiveModel(options: LocalModelLoadingOptions = LocalModelLoadingOptions()) async {
        await run {
            let engine = try await composition.activeLocalModelEngine()
            guard let engine else {
                throw LocalModelStorageError.storageCorrupt("No active model engine available to load")
            }
            self.activeEngine = engine
            try await engine.load(options: options)
            activeEngineLifecycle = await engine.lifecycleState
        }
    }

    func unloadActiveModel() async {
        await run {
            if let activeEngine {
                try await activeEngine.unload()
                activeEngineLifecycle = await activeEngine.lifecycleState
            } else {
                let engine = try await composition.activeLocalModelEngine()
                if let engine {
                    try await engine.unload()
                    activeEngineLifecycle = await engine.lifecycleState
                }
            }
        }
    }

    func deleteModel(id: ModelID) async {
        await run {
            if activeModelDescriptor?.id == id, let activeEngine {
                try? await activeEngine.unload()
            }
            try await composition.localModelStorage.deleteModel(id: id)
            await refreshModels()
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
