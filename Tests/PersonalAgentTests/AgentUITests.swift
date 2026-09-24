import Foundation
import Testing
import PAFoundation
import PAKernel
import PAComposition
import PAArchitecture
import PAProviders
import PAAgency
import PACognition
import PAModules

@MainActor
@Suite("Agent UI & Task Execution Pipeline Tests")
struct AgentUITests {

    @Test func testInitialIdleState() {
        let pipeline = AgentTaskExecutionPipeline()

        #expect(pipeline.state == .idle)
        #expect(pipeline.currentTask.isEmpty)
        #expect(pipeline.reasoningStatus == .pending)
        #expect(pipeline.actionStatus == .pending)
        #expect(pipeline.observationStatus == .pending)
        #expect(pipeline.verificationStatus == .pending)
        #expect(pipeline.resultSummary == nil)
        #expect(pipeline.userSafeFailureReason == nil)
        #expect(pipeline.validationError == nil)
    }

    @Test func testEmptyTaskValidation() {
        let validationError = AgentTaskExecutionPipeline.validateTask("   ")
        #expect(validationError == "Please enter a task before running.")

        let validResult = AgentTaskExecutionPipeline.validateTask("Run a valid task")
        #expect(validResult == nil)
    }

    @Test func testStartPipelineTransition() {
        let pipeline = AgentTaskExecutionPipeline.startPipeline(task: "  Sample task  ")

        #expect(pipeline.currentTask == "Sample task")
        #expect(pipeline.state == .running)
        #expect(pipeline.reasoningStatus == .inProgress)
        #expect(pipeline.actionStatus == .pending)
        #expect(pipeline.observationStatus == .pending)
        #expect(pipeline.verificationStatus == .pending)
    }

    @Test func testSuccessfulTaskExecutionAndVerification() async throws {
        let root = try await M8CompositionRoot(modules: [EchoModule()])

        var pipeline = AgentTaskExecutionPipeline.startPipeline(task: "Echo hello world")
        let goalID = try await root.session.submitInput(pipeline.currentTask)

        let eval = try await root.orchestrator.run(goalID: goalID)
        let events = try await root.eventLog.allEvents()

        pipeline.updateFromEvents(events, goalID: goalID, eval: eval)

        #expect(pipeline.state == .completed)
        #expect(pipeline.reasoningStatus == .completed)
        #expect(pipeline.actionStatus == .completed)
        #expect(pipeline.observationStatus == .completed)
        #expect(pipeline.verificationStatus == .completed)
        #expect(pipeline.resultSummary != nil)
        #expect(pipeline.userSafeFailureReason == nil)
    }

    @Test func testFailedTaskExecutionHandling() async throws {
        let root = try await M8CompositionRoot() // No modules registered
        let rejectingVerifier = RejectingVerifier()

        let orchestrator = M6Orchestrator(
            runtime: root.runtime,
            eventLog: root.eventLog,
            verifier: rejectingVerifier
        )

        var pipeline = AgentTaskExecutionPipeline.startPipeline(task: "Unverified task proposal")
        let goalID = try await root.session.submitInput(pipeline.currentTask)

        let eval = try await orchestrator.run(goalID: goalID)
        let events = try await root.eventLog.allEvents()

        pipeline.updateFromEvents(events, goalID: goalID, eval: eval)

        #expect(pipeline.state == .failed)
        #expect(pipeline.userSafeFailureReason == "Verification rejected")
        #expect(pipeline.resultSummary == nil)
    }

    @Test func testResetTaskClearsState() {
        var pipeline = AgentTaskExecutionPipeline.startPipeline(task: "Test reset task")
        #expect(pipeline.state == .running)

        pipeline = AgentTaskExecutionPipeline()
        #expect(pipeline.state == .idle)
        #expect(pipeline.currentTask.isEmpty)
        #expect(pipeline.reasoningStatus == .pending)
        #expect(pipeline.actionStatus == .pending)
        #expect(pipeline.observationStatus == .pending)
        #expect(pipeline.verificationStatus == .pending)
        #expect(pipeline.resultSummary == nil)
        #expect(pipeline.userSafeFailureReason == nil)
    }
}

private struct RejectingVerifier: Verifying {
    func verify(plan: Plan, proposals: [ActionProposal]) async throws -> VerificationResult {
        VerificationResult(accepted: false, notes: "Unsafe parameters detected")
    }
}

private struct EchoModule: Module {
    let contract = ModuleContract(
        id: ModuleID(rawValue: "mod.echo"),
        name: "Echo Module",
        version: SemanticVersion(major: 1, minor: 0, patch: 0),
        kind: .atomic,
        capabilities: .read,
        inputSchema: SchemaDocument(identifier: "echo.in"),
        outputSchema: SchemaDocument(identifier: "echo.out"),
        requiredFields: ["text"]
    )

    func execute(_ input: ModulePayload) async throws -> ModulePayload {
        let text = input.fields["text"] ?? ""
        return ModulePayload(
            schema: contract.outputSchema,
            fields: ["output": "Echo: \(text)"]
        )
    }
}
