import Foundation
import SwiftUI
import PAFoundation
import PAKernel
import PAComposition
import PAArchitecture
import PAProviders
import PAEvents
import PACognition
import PAAgency

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

    // M10.0 Task & Agent OS Execution State
    @Published var pipeline: AgentTaskExecutionPipeline = AgentTaskExecutionPipeline()

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

    // Convenience computed getters for UI binding
    var currentTask: String { pipeline.currentTask }
    var executionState: AgentTaskExecutionState { pipeline.state }
    var reasoningStatus: ExecutionStepStatus { pipeline.reasoningStatus }
    var actionStatus: ExecutionStepStatus { pipeline.actionStatus }
    var observationStatus: ExecutionStepStatus { pipeline.observationStatus }
    var verificationStatus: ExecutionStepStatus { pipeline.verificationStatus }
    var reasoningSummary: String? { pipeline.reasoningSummary }
    var actionSummary: String? { pipeline.actionSummary }
    var observationSummary: String? { pipeline.observationSummary }
    var verificationSummary: String? { pipeline.verificationSummary }
    var resultSummary: String? { pipeline.resultSummary }
    var userSafeFailureReason: String? { pipeline.userSafeFailureReason }
    var emptyTaskValidationError: String? { pipeline.validationError }

    func refresh() async {
        state = await composition.session.currentState()
        goals = await composition.session.activeGoals()
        providerID = await composition.currentProviderIdentityID()
        providerLifecycle = await composition.currentProviderLifecycle()
        moduleIDs = await composition.registeredModuleIDs()

        let storage = composition.localModelStorage
        do {
            installedModels = try await storage.listModels()
            activeModelID = try await storage.activeModelID()
            activeModelDescriptor = try await storage.activeModelDescriptor()
        } catch {
            installedModels = []
            activeModelID = nil
            activeModelDescriptor = nil
            lastError = String(describing: error)
        }

        do {
            if let engine = try await composition.activeLocalModelEngine() {
                activeEngineState = await engine.lifecycleState
            } else {
                activeEngineState = .unloaded
            }
        } catch {
            activeEngineState = .failed(reason: error.localizedDescription)
            lastError = String(describing: error)
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

    // M10.0 Task Execution Entry Point
    func runTask(_ statement: String) async {
        if let errorMsg = AgentTaskExecutionPipeline.validateTask(statement) {
            pipeline.validationError = errorMsg
            return
        }

        pipeline = AgentTaskExecutionPipeline.startPipeline(task: statement)

        do {
            let execution = try await composition.executeAgentTask(pipeline.currentTask)
            pipeline.updateFromEvents(
                execution.events,
                goalID: execution.goalID,
                eval: execution.evaluation
            )
        } catch {
            if pipeline.reasoningStatus == .inProgress { pipeline.reasoningStatus = .failed }
            else if pipeline.actionStatus == .inProgress { pipeline.actionStatus = .failed }
            else if pipeline.observationStatus == .inProgress { pipeline.observationStatus = .failed }
            else if pipeline.verificationStatus == .inProgress { pipeline.verificationStatus = .failed }

            pipeline.state = .failed
            pipeline.userSafeFailureReason = error.localizedDescription
            lastError = String(describing: error)
        }

        await refresh()
    }

    func retryTask() async {
        guard !pipeline.currentTask.isEmpty else { return }
        await runTask(pipeline.currentTask)
    }

    func resetTask() {
        pipeline = AgentTaskExecutionPipeline()
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
