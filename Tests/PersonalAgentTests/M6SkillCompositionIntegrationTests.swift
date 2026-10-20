import Foundation
import Testing
import PAKernel
import PARuntime
import PAEvents
import PASkills
import PAModules
@testable import PAComposition

@Suite("Canonical M6 Skill Composition")
struct M6SkillCompositionIntegrationTests {
    private struct AllowPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("integration test grant") }
    }

    private struct ModuleApprovalPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            if intent.summary.hasPrefix("Execute skill ") {
                return .allow("skill boundary allowed")
            }
            if intent.summary.hasPrefix("Execute Module ") {
                return .approve("module execution requires approval")
            }
            return .deny("unexpected action: \(intent.summary)")
        }
    }


    private struct ReadOnlyManifestExecutor: SkillExecutor {
        func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
            #"{ "text": "read-only capability executed" }"#
        }
        func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
            guard let data = outputJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
            return object["text"] == "read-only capability executed"
        }
    }

    private struct UntrustedRegisteredExecutor: SkillExecutor {
        func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
            #"{"result":"executed"}"#
        }
        func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
            outputJSON == #"{"result":"executed"}"#
        }
    }

    @Test("orchestrator refuses to run without an explicit Agent scope")
    func orchestratorRequiresExplicitAgentScope() async throws {
        let orchestrator = SkillAgentOrchestrator()
        await #expect(throws: SkillAgentOrchestratorError.agentScopeRequired) {
            _ = try await orchestrator.run(
                goalStatement: "Text Normalize",
                inputJSON: #"{ "text": "input" }"#,
                policy: AllowPolicy()
            )
        }
    }

    @Test("public M8 Skill APIs enforce the active default Agent scope")
    func publicSkillAPIsRespectDefaultAgentScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skillsDirectory = directory.appendingPathComponent("Skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        let customSkill = """
        id: custom.unscoped
        name: Unscoped Skill
        version: 1.0.0
        description: A discoverable Skill not declared by the default Agent.
        ---
        ## Input
        custom.unscoped.input

        ## Output
        custom.unscoped.output

        ## Rule
        Return the registered executor result.
        """
        try customSkill.write(
            to: skillsDirectory.appendingPathComponent("custom.unscoped.Skill.md"),
            atomically: true,
            encoding: .utf8
        )

        let skillID = SkillID(rawValue: "custom.unscoped")
        let registry = SkillExecutorRegistry()
        await registry.register(UntrustedRegisteredExecutor(), for: skillID.rawValue)
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            skillExecutors: registry
        )

        #expect(try await root.discoverSkills().contains { $0.id == skillID })
        #expect(await root.skillExecutorAvailability(for: skillID) == .available)

        await #expect(throws: SkillExecutionError.noSelection) {
            _ = try await root.selectSkill(goalStatement: skillID.rawValue)
        }
        await #expect(throws: SkillAgentOrchestratorError.skillOutsideAgentScope(skillID)) {
            _ = try await root.executeSkill(id: skillID, inputJSON: "{}", policy: AllowPolicy())
        }
        await #expect(throws: SkillExecutionError.noSelection) {
            _ = try await root.runSkillAgent(
                goalStatement: skillID.rawValue,
                inputJSON: "{}",
                policy: AllowPolicy()
            )
        }
    }

    @Test("M8 preflight deterministically clarifies incomplete file intents")
    func m8PreflightClassifiesIncompleteAndCompleteFileRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )

        let incompletePrompts = [
            "Tạo file",
            "hãy tạo file hello.txt",
            "Hãy tạo tệp báo cáo.md",
            "Please create a file report.md",
            "write file draft.txt",
            "Tạo file với nội dung: chưa có tên file",
            "Create file with content: missing filename"
        ]
        for prompt in incompletePrompts {
            guard case .needsClarification(let message) = root.preflightChatRequest(goalStatement: prompt) else {
                Issue.record("Expected deterministic clarification for: \(prompt)")
                continue
            }
            #expect(!message.isEmpty)
            #expect(try await root.runChatSkillIfMatched(goalStatement: prompt) == nil)
        }

        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.write"
        })
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/hello.txt").path))

        let completePrompts = [
            "Hãy tạo file workspace/hello.txt với nội dung: Xin chào",
            "Please create a file workspace/report.md with content: status ok",
            "Tạo một tệp workspace/empty.txt với nội dung:"
        ]
        for prompt in completePrompts {
            #expect(root.preflightChatRequest(goalStatement: prompt) == .continueRouting)
        }

        let unsafeOrAmbiguousPaths = [
            "Tạo file hello.txt với nội dung: Xin chào",
            "Tạo file /tmp/hello.txt với nội dung: Xin chào",
            "Tạo file workspace/../hello.txt với nội dung: Xin chào",
            "Tạo file unknown-root/hello.txt với nội dung: Xin chào"
        ]
        for prompt in unsafeOrAmbiguousPaths {
            guard case .needsClarification = root.preflightChatRequest(goalStatement: prompt) else {
                Issue.record("Expected path clarification for: \\(prompt)")
                continue
            }
        }

        #expect(root.preflightChatRequest(
            goalStatement: "Explain how Python async works"
        ) == .continueRouting)

        #expect(AgentExecutionOutcome.needsClarification("content").statusName == "needs_clarification")
        #expect(AgentExecutionOutcome.denied("policy").statusName == "denied")
        #expect(AgentExecutionOutcome.executionFailed("io").statusName == "execution_failed")
        #expect(AgentExecutionOutcome.verifiedSuccess("written").statusName == "verified_success")
    }

    @Test("registered Skill executes and verifies through canonical composition")
    func executesVerifiedSkill() async throws {
        let manifest = SkillRuntime.normalizationManifest
        let root = try await M6CompositionRoot(
            policy: AllowPolicy(),
            skillStore: InMemorySkillStore(manifests: [manifest]),
            skillExecutors: SkillExecutorRegistry(executors: [
                manifest.id.rawValue: TextNormalizeSkillExecutor()
            ]),
            allowedSkillIDs: [manifest.id]
        )
        let goal = Goal(statement: manifest.id.rawValue)
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)
        let events = try await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == manifest.id.rawValue
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }


    @Test("M6 adds the required execute capability to read-only Skill grants")
    func m6ReadOnlyManifestReceivesExecutionCapability() async throws {
        let id = SkillID(rawValue: "custom.read-only")
        let manifest = SkillManifest(
            id: id,
            name: "Read Only Skill",
            description: "A Skill with read-only declared capabilities.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return the fixed verified result.",
            inputSchema: SchemaDocument(identifier: "custom.read-only.input"),
            outputSchema: SchemaDocument(identifier: "custom.read-only.output"),
            requiredCapabilities: .read
        )
        let root = try await M6CompositionRoot(
            provider: DeterministicFakeProvider(),
            policy: AllowPolicy(),
            skillStore: InMemorySkillStore(manifests: [manifest]),
            skillExecutors: SkillExecutorRegistry(executors: [id.rawValue: ReadOnlyManifestExecutor()]),
            allowedSkillIDs: [id]
        )
        let goal = Goal(statement: id.rawValue)
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)
        let events = try await (root.eventLog as? InMemoryEventLog)?.allEvents() ?? []
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == id.rawValue
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }


    private struct WriteCapabilityModule: Module {
        let contract = ModuleContract(
            id: ModuleID(rawValue: "tool.workspace.write"),
            name: "Workspace Write",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .atomic,
            capabilities: .write,
            inputSchema: SchemaDocument(identifier: "tool.workspace.write.input"),
            outputSchema: SchemaDocument(identifier: "tool.workspace.write.output"),
            requiredFields: ["arguments"]
        )
        func execute(_ input: ModulePayload) async throws -> ModulePayload {
            ModulePayload(schema: contract.outputSchema, fields: ["output": "{}"])
        }
    }

    @Test("M6 authorizes the actual Module capability for a module-backed Skill")
    func m6ModuleBackedSkillUsesConcreteModuleCapabilities() async throws {
        let id = SkillID(rawValue: "workspace.create-file")
        let manifest = SkillManifest(
            id: id,
            name: "Tạo File",
            description: "Create a file in the workspace.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Create a file in workspace.",
            inputSchema: SchemaDocument(identifier: "tool.workspace.write.input"),
            outputSchema: SchemaDocument(identifier: "tool.workspace.write.output"),
            requiredCapabilities: [.read, .execute],
            metadata: [
                "moduleID": "tool.workspace.write",
                "chatInputAdapter": "workspace.create-file"
            ]
        )
        let moduleRuntime = ModuleRuntime(
            catalog: try ModuleCatalog(modules: [WriteCapabilityModule()]),
            grantedCapabilities: [.read, .write, .execute],
            policy: AllowPolicy()
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )
        let adapter = M6SkillExecutionAdapter(runtime: runtime, allowedSkillIDs: [id])
        let capabilities = try await adapter.requiredCapabilities(for: id)
        #expect(capabilities == [.read, .write, .execute])
    }



    @Test("M6 fails closed when a built-in module-backed Skill binding is mismatched")
    func m6ModuleBackedSkillRejectsMismatchedBinding() async throws {
        let id = SkillID(rawValue: "workspace.create-file")
        let manifest = SkillManifest(
            id: id,
            name: "Tạo File",
            description: "Create a file in the workspace.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Create a file in workspace.",
            inputSchema: SchemaDocument(identifier: "tool.workspace.write.input"),
            outputSchema: SchemaDocument(identifier: "tool.workspace.write.output"),
            requiredCapabilities: [.read, .execute],
            metadata: [
                "moduleID": "tool.workspace.read",
                "chatInputAdapter": "workspace.create-file"
            ]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        let adapter = M6SkillExecutionAdapter(runtime: runtime, allowedSkillIDs: [id])
        await #expect(throws: SkillExecutionError.malformedSkill) {
            _ = try await adapter.requiredCapabilities(for: id)
        }
    }

    @Test("M6 fails closed when a module-backed Skill schema differs from its Module")
    func m6ModuleBackedSkillRejectsSchemaMismatch() async throws {
        let id = SkillID(rawValue: "workspace.create-file")
        let manifest = SkillManifest(
            id: id,
            name: "Tạo File",
            description: "Create a file in the workspace.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Create a file in workspace.",
            inputSchema: SchemaDocument(identifier: "tool.workspace.write.input"),
            outputSchema: SchemaDocument(identifier: "incorrect.output"),
            requiredCapabilities: [.read, .execute],
            metadata: [
                "moduleID": "tool.workspace.write",
                "chatInputAdapter": "workspace.create-file"
            ]
        )
        let moduleRuntime = ModuleRuntime(
            catalog: try ModuleCatalog(modules: [WriteCapabilityModule()]),
            grantedCapabilities: [.read, .write, .execute],
            policy: AllowPolicy()
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), moduleRuntime: moduleRuntime)
        let adapter = M6SkillExecutionAdapter(runtime: runtime, allowedSkillIDs: [id])
        await #expect(throws: SkillExecutionError.malformedSkill) {
            _ = try await adapter.requiredCapabilities(for: id)
        }
    }


    @Test("M8 module-backed Skill fails closed when ModuleRuntime requires approval")
    func m8ModuleBackedSkillFailsClosedWhenApprovalRequired() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: ModuleApprovalPolicy(),
            workspaceToolsEnabled: true
        )

        // SkillRuntime allows the Skill; the second policy boundary in ModuleRuntime
        // requires approval and must reject before invoking the workspace tool.
        await #expect(throws: ModuleRuntimeError.capabilityDenied(.read)) {
            _ = try await root.runChatSkillIfMatched(goalStatement: "Tìm kiếm workspace approval-sentinel")
        }
        let events = try await eventLog.allEvents()
        #expect(events.contains { $0.kind == .moduleFailed })
        #expect(!events.contains { $0.kind == .moduleInvoked })
    }


    private struct ApprovingModuleGate: ApprovalGate {
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            intent.summary.hasPrefix("Execute Module ")
        }
    }

    private actor SkillExecutorCallCounter {
        private var calls = 0
        func increment() { calls += 1 }
        func value() -> Int { calls }
    }

    private struct CountingSkillExecutor: SkillExecutor {
        let counter: SkillExecutorCallCounter
        func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
            await counter.increment()
            return #"{ "text": "approved" }"#
        }
        func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
            guard let data = outputJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
            return object["text"] == "approved"
        }
    }

    private struct DirectSkillApprovalPolicy: PolicyEvaluating {
        func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
            .approve("direct Skill approval required")
        }
    }

    private struct DirectSkillApprovalGate: ApprovalGate {
        let expectedSkillID: SkillID
        let approved: Bool
        func requestApproval(for intent: ActionIntent) async throws -> Bool {
            guard intent.skillID == expectedSkillID,
                  intent.capabilities.contains(.execute) else { return false }
            return approved
        }
    }

    @Test("M8 direct Skill Agent executes only after typed Skill approval")
    func m8DirectSkillAgentExecutesAfterSkillApproval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skillID = SkillRuntime.normalizationManifest.id
        let counter = SkillExecutorCallCounter()
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: skillID.rawValue)
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            approvalGate: DirectSkillApprovalGate(expectedSkillID: skillID, approved: true),
            skillExecutors: registry
        )

        let result = try await root.runSkillAgent(
            goalStatement: skillID.rawValue,
            inputJSON: #"{ "text": "input" }"#,
            policy: DirectSkillApprovalPolicy()
        )
        #expect(result.skillID == skillID)
        #expect(result.verified)
        #expect(await counter.value() == 1)
    }

    @Test("M8 explicit executeSkill API honors the same approval boundary")
    func m8ExecuteSkillUsesApprovalBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skillID = SkillRuntime.normalizationManifest.id
        let counter = SkillExecutorCallCounter()
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: skillID.rawValue)
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            approvalGate: DirectSkillApprovalGate(expectedSkillID: skillID, approved: true),
            skillExecutors: registry
        )

        let output = try await root.executeSkill(
            id: skillID,
            inputJSON: #"{ "text": "input" }"#,
            policy: DirectSkillApprovalPolicy()
        )
        #expect(output == #"{ "text": "approved" }"#)
        #expect(await counter.value() == 1)
    }

    @Test("M8 direct Skill Agent never executes after approval rejection")
    func m8DirectSkillAgentDoesNotExecuteAfterApprovalRejection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skillID = SkillRuntime.normalizationManifest.id
        let counter = SkillExecutorCallCounter()
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: skillID.rawValue)
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            approvalGate: DirectSkillApprovalGate(expectedSkillID: skillID, approved: false),
            skillExecutors: registry
        )

        await #expect(throws: SkillExecutionError.policyDenied("Approval not granted")) {
            _ = try await root.runSkillAgent(
                goalStatement: skillID.rawValue,
                inputJSON: #"{ "text": "input" }"#,
                policy: DirectSkillApprovalPolicy()
            )
        }
        #expect(await counter.value() == 0)
    }

    @Test("M8 direct Skill Agent fails closed when approval is required but no gate exists")
    func m8DirectSkillAgentRequiresApprovalGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skillID = SkillRuntime.normalizationManifest.id
        let counter = SkillExecutorCallCounter()
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: skillID.rawValue)
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            skillExecutors: registry
        )

        await #expect(throws: SkillExecutionError.policyRequiresApproval("direct Skill approval required")) {
            _ = try await root.runSkillAgent(
                goalStatement: skillID.rawValue,
                inputJSON: #"{ "text": "input" }"#,
                policy: DirectSkillApprovalPolicy()
            )
        }
        #expect(await counter.value() == 0)
    }

    @Test("M8 module-backed Skill runs only after explicit Module approval")
    func m8ModuleBackedSkillRunsAfterModuleApproval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: ModuleApprovalPolicy(),
            approvalGate: ApprovingModuleGate(),
            workspaceToolsEnabled: true
        )
        let result = try await root.runChatSkillIfMatched(
            goalStatement: "Tìm kiếm workspace approval-sentinel"
        )
        #expect(result?.verified == true)
        let events = try await eventLog.allEvents()
        #expect(events.contains { $0.kind == .moduleInvoked })
        #expect(events.contains { $0.kind == .moduleCompleted })
    }

    @Test("M8 canonical chat loop executes and verifies a declared Skill")
    func m8CanonicalLoopExecutesSkill() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let goal = Goal(statement: "text.normalize")
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)
        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "text.normalize"
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 Skill availability reflects registered workspace tool contracts")
    func m8SkillAvailabilityTracksWorkspaceToolRegistration() async throws {
        let enabledDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: enabledDirectory) }
        let enabledRoot = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: enabledDirectory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let workspaceSearch = SkillID(rawValue: "workspace.search")
        #expect(await enabledRoot.skillExecutorAvailability(for: workspaceSearch) == .available)

        let disabledDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: disabledDirectory) }
        let disabledRoot = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: disabledDirectory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )
        #expect(await disabledRoot.skillExecutorAvailability(for: workspaceSearch) == .unavailable)
    }

    @Test("M8 workspace Skill creates and verifies a real file")
    func m8WorkspaceSkillCreatesVerifiedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let content = "Skill wrote this file."
        let goal = Goal(statement: "Tạo file workspace/notes.md với nội dung: \(content)")
        try await root.runtime.submit(goal: goal)
        let evaluation = try await root.orchestrator.run(goalID: goal.id)
        #expect(evaluation.disposition == .complete)

        let fileURL = directory.appendingPathComponent("workspace/notes.md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)

        let events = try await eventLog.allEvents()
        let observation = events.first {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.create-file"
        }
        #expect(observation?.payload["succeeded"] == "true")
        #expect(observation?.payload["verified"] == "true")
    }

    @Test("M8 Agent team normalizes polite Vietnamese create-file commands")
    func m8AgentTeamCreatesFileFromPoliteRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let content = "Nội dung qua Agent team"
        let contextualInput = """
        Conversation context:
        user: Hãy tạo file workspace/old.md với nội dung: nội dung cũ

        Response preference: Reply in natural Vietnamese.
        Current user request:
        Hãy tạo file workspace/team-polite.md với nội dung: \(content)
        """
        let result = try await root.runChatTeamIfMatched(
            goalStatement: "Tạo file workspace/team-polite.md với nội dung: \(content)",
            inputContext: contextualInput
        )
        #expect(result?.members.contains {
            $0.skillResult.skillID.rawValue == "workspace.create-file" && $0.skillResult.verified
        } == true)

        let fileURL = directory.appendingPathComponent("workspace/team-polite.md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)
    }

    @Test("M8 workspace Skill accepts polite Vietnamese create-file commands")
    func m8WorkspaceSkillCreatesFileFromPoliteRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let content = "Nội dung đã tạo thật"
        let result = try await root.runChatSkillIfMatched(
            goalStatement: "Hãy tạo file workspace/polite.md với nội dung: \(content)"
        )
        #expect(result?.skillID.rawValue == "workspace.create-file")
        #expect(result?.verified == true)

        let fileURL = directory.appendingPathComponent("workspace/polite.md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == content)
    }

    @Test("M8 workspace search finds a real matching file through the Skill loop")
    func m8WorkspaceSearchFindsMatchingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try "A unique needle appears here.".write(
            to: workspace.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        let fakeSecret = "api_key = \"sk-" + String(repeating: "A", count: 24) + "\" needle"
        try fakeSecret.write(
            to: workspace.appendingPathComponent("secret.md"),
            atomically: true,
            encoding: .utf8
        )
        let protectedDirectory = workspace.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        try "ordinary content".write(
            to: protectedDirectory.appendingPathComponent("note.md"),
            atomically: true,
            encoding: .utf8
        )
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )

        let skills = try await root.discoverSkills()
        #expect(skills.contains { $0.id.rawValue == "workspace.search" })
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.contains { $0.rawValue == "workspace.search" })

        let result = try await root.runChatSkillIfMatched(goalStatement: "Tìm kiếm workspace needle")
        #expect(result?.skillID.rawValue == "workspace.search")
        #expect(result?.verified == true)
        let resultEnvelope = try JSONSerialization.jsonObject(
            with: Data((result?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let resultPayload = try JSONSerialization.jsonObject(
            with: Data((resultEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(resultPayload?["query"] as? String == "needle")
        #expect(resultPayload?["matches"] as? [String] == ["workspace/notes.md"])

        let politeResult = try await root.runChatSkillIfMatched(
            goalStatement: "Hãy tìm kiếm trong workspace needle"
        )
        #expect(politeResult?.skillID.rawValue == "workspace.search")
        #expect(politeResult?.verified == true)
        let politeEnvelope = try JSONSerialization.jsonObject(
            with: Data((politeResult?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let politePayload = try JSONSerialization.jsonObject(
            with: Data((politeEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(politePayload?["query"] as? String == "needle")
        #expect(politePayload?["matches"] as? [String] == ["workspace/notes.md"])

        let englishResult = try await root.runChatSkillIfMatched(
            goalStatement: "Search workspace for needle"
        )
        #expect(englishResult?.skillID.rawValue == "workspace.search")
        #expect(englishResult?.verified == true)
        let englishEnvelope = try JSONSerialization.jsonObject(
            with: Data((englishResult?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let englishPayload = try JSONSerialization.jsonObject(
            with: Data((englishEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(englishPayload?["query"] as? String == "needle")
        #expect(englishPayload?["matches"] as? [String] == ["workspace/notes.md"])

        let noMatch = try await root.runChatSkillIfMatched(
            goalStatement: "Search workspace for absenttoken"
        )
        #expect(noMatch?.skillID.rawValue == "workspace.search")
        #expect(noMatch?.verified == true)
        let noMatchEnvelope = try JSONSerialization.jsonObject(
            with: Data((noMatch?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let noMatchPayload = try JSONSerialization.jsonObject(
            with: Data((noMatchEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(noMatchPayload?["matches"] as? [String] == [])

        for emptySearch in ["Hãy tìm kiếm trong workspace", "Search workspace"] {
            var rejectedAsMalformed = false
            do {
                _ = try await root.runChatSkillIfMatched(goalStatement: emptySearch)
            } catch let error as SkillExecutionError {
                rejectedAsMalformed = error == .malformedSkill
            }
            #expect(rejectedAsMalformed)
        }

        let readResult = try await root.runChatSkillIfMatched(
            goalStatement: "Đọc file workspace/notes.md"
        )
        #expect(readResult?.skillID.rawValue == "workspace.read-file")
        #expect(readResult?.verified == true)
        let readEnvelope = try JSONSerialization.jsonObject(
            with: Data((readResult?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let readPayload = try JSONSerialization.jsonObject(
            with: Data((readEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(readPayload?["operation"] as? String == "read")
        #expect(readPayload?["verified"] as? Bool == true)
        #expect(readPayload?["path"] as? String == "workspace/notes.md")
        #expect(readPayload?["content"] as? String == "A unique needle appears here.")
        #expect(readPayload?["bytes"] as? Int == "A unique needle appears here.".utf8.count)

        let englishRead = try await root.runChatSkillIfMatched(
            goalStatement: "Read file workspace/notes.md"
        )
        #expect(englishRead?.skillID.rawValue == "workspace.read-file")
        #expect(englishRead?.verified == true)
        let englishReadEnvelope = try JSONSerialization.jsonObject(
            with: Data((englishRead?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let englishReadPayload = try JSONSerialization.jsonObject(
            with: Data((englishReadEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(englishReadPayload?["content"] as? String == "A unique needle appears here.")
        #expect(englishReadPayload?["bytes"] as? Int == "A unique needle appears here.".utf8.count)

        // Direct read phrasing includes the workspace root in the prefix. It must
        // preserve that root through parsing and return verified content.
        let directVietnameseRead = try await root.runChatSkillIfMatched(
            goalStatement: "Đọc workspace/notes.md"
        )
        #expect(directVietnameseRead?.skillID.rawValue == "workspace.read-file")
        #expect(directVietnameseRead?.verified == true)
        let directReadEnvelope = try JSONSerialization.jsonObject(
            with: Data((directVietnameseRead?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let directReadPayload = try JSONSerialization.jsonObject(
            with: Data((directReadEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(directReadPayload?["path"] as? String == "workspace/notes.md")
        #expect(directReadPayload?["content"] as? String == "A unique needle appears here.")
        #expect(directReadPayload?["verified"] as? Bool == true)

        let politeRead = try await root.runChatSkillIfMatched(
            goalStatement: "Hãy đọc file workspace/notes.md"
        )
        #expect(politeRead?.skillID.rawValue == "workspace.read-file")
        #expect(politeRead?.verified == true)
        let politeReadEnvelope = try JSONSerialization.jsonObject(
            with: Data((politeRead?.outputJSON ?? "{}").utf8)
        ) as? [String: String]
        let politeReadPayload = try JSONSerialization.jsonObject(
            with: Data((politeReadEnvelope?["output"] ?? "{}").utf8)
        ) as? [String: Any]
        #expect(politeReadPayload?["path"] as? String == "workspace/notes.md")
        #expect(politeReadPayload?["content"] as? String == "A unique needle appears here.")
        #expect(politeReadPayload?["verified"] as? Bool == true)

        let directEnglishRead = try await root.runChatSkillIfMatched(
            goalStatement: "Read workspace/notes.md"
        )
        #expect(directEnglishRead?.skillID.rawValue == "workspace.read-file")
        #expect(directEnglishRead?.verified == true)

        var missingReadRejected = false
        do {
            _ = try await root.runChatSkillIfMatched(
                goalStatement: "Read file workspace/missing.md"
            )
        } catch {
            missingReadRejected = true
        }
        #expect(missingReadRejected)

        var secretReadRejected = false
        do {
            _ = try await root.runChatSkillIfMatched(
                goalStatement: "Read file workspace/secret.md"
            )
        } catch {
            secretReadRejected = true
        }
        #expect(secretReadRejected)

        var protectedReadRejected = false
        do {
            _ = try await root.runChatSkillIfMatched(
                goalStatement: "Read file workspace/secrets/note.md"
            )
        } catch {
            protectedReadRejected = true
        }
        #expect(protectedReadRejected)

        var traversalReadRejected = false
        do {
            _ = try await root.runChatSkillIfMatched(
                goalStatement: "Read file workspace/../workspace/notes.md"
            )
        } catch {
            traversalReadRejected = true
        }
        #expect(traversalReadRejected)
    }

    @Test("M8 chat does not expose workspace Skills when workspace tools are disabled")
    func m8WorkspaceSkillsRemainOutOfScopeWhenDisabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )

        let createResult = try await root.runChatSkillIfMatched(
            goalStatement: "Tạo file workspace/blocked.md với nội dung: must not be written"
        )
        let searchResult = try await root.runChatSkillIfMatched(
            goalStatement: "Tìm kiếm workspace secretneedle"
        )
        let readResult = try await root.runChatSkillIfMatched(
            goalStatement: "Đọc file workspace/blocked.md"
        )
        let teamSearchResult = try await root.runChatTeamIfMatched(
            goalStatement: "Search workspace for secretneedle"
        )
        let teamReadResult = try await root.runChatTeamIfMatched(
            goalStatement: "Read file workspace/blocked.md"
        )
        #expect(createResult == nil)
        #expect(searchResult == nil)
        #expect(readResult == nil)
        #expect(teamSearchResult == nil)
        #expect(teamReadResult == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/blocked.md").path))

        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.read"
        })
        #expect(!events.contains {
            $0.kind == .observationProduced && $0.payload["skillID"] == "workspace.search"
        })
    }

    @Test("Workspace Skills stay out of scope after agent-specific selection")
    func workspaceSkillsCannotLeakThroughCustomAgentScopeWhenDisabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skills = directory.appendingPathComponent("Skills", isDirectory: true)
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let unrelatedSkill = """
        id: workspace.query
        name: Workspace Query
        version: 1.0.0
        description: A helper for workspace search queries.
        ---
        ## Input
        workspace.query.input

        ## Output
        workspace.query.output

        ## Rule
        Describe a workspace query.
        """
        try unrelatedSkill.write(
            to: skills.appendingPathComponent("workspace.query.Skill.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspaceOnlyAgent = """
        id: personal.workspace-only
        name: Workspace-only Agent
        version: 1.0.0
        description: Only workspace search and read Skills are allowed.
        ---
        ## Skills
        workspace.search
        workspace.read-file

        ## Rule
        Search or read workspace content only when the workspace capability is enabled.
        """
        try workspaceOnlyAgent.write(
            to: agents.appendingPathComponent("personal.workspace-only.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: false
        )

        let direct = try await root.runChatSkillIfMatched(
            goalStatement: "Tìm kiếm workspace secretneedle",
            agentID: "personal.workspace-only"
        )
        let directRead = try await root.runChatSkillIfMatched(
            goalStatement: "Đọc file workspace/blocked.md",
            agentID: "personal.workspace-only"
        )
        let team = try await root.runChatTeamIfMatched(goalStatement: "Tìm kiếm workspace secretneedle")
        let teamRead = try await root.runChatTeamIfMatched(goalStatement: "Đọc file workspace/blocked.md")
        #expect(direct == nil)
        #expect(directRead == nil)
        #expect(team == nil)
        #expect(teamRead == nil)

        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.read"
        })
    }

    @Test("Default Agent migrates only the exact previous built-in scope")
    func defaultAgentMigratesPreviousBuiltInScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let previousDefault = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent.
        ---
        ## Skills
        text.normalize
        workspace.create-file

        ## Rule
        Select only from the declared skills. Use the workspace.create-file Skill for explicit file creation requests.
        """
        try previousDefault.write(
            to: agents.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.contains { $0.rawValue == "workspace.search" })
    }

    @Test("Default Agent migrates the exact previous search-enabled scope")
    func defaultAgentMigratesPreviousSearchScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let previousDefault = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Default personal agent.
        ---
        ## Skills
        text.normalize
        workspace.create-file
        workspace.search

        ## Rule
        Select only from the declared skills. Use workspace.create-file for explicit file creation requests and workspace.search to find content in permitted workspace files.
        """
        try previousDefault.write(
            to: agents.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.contains { $0.rawValue == "workspace.read-file" })
    }

    @Test("An imported Skill cannot borrow the built-in workspace write adapter")
    func importedSkillCannotBorrowWorkspaceWriteAdapter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skills = directory.appendingPathComponent("Skills", isDirectory: true)
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)

        let untrustedSkill = """
        id: untrusted.create-file
        name: Tạo File
        version: 1.0.0
        description: An imported Skill attempting to reuse the built-in file writer.
        moduleID: tool.workspace.write
        chatInputAdapter: workspace.create-file
        ---
        ## Input
        tool.workspace.write.input

        ## Output
        tool.workspace.write.output

        ## Rule
        Attempt to create a file using a copied built-in adapter.
        """
        try untrustedSkill.write(
            to: skills.appendingPathComponent("untrusted.create-file.Skill.md"),
            atomically: true,
            encoding: .utf8
        )
        let agentManifest = """
        id: personal.untrusted
        name: Untrusted Skill Agent
        version: 1.0.0
        description: Runs only the imported Skill under test.
        ---
        ## Skills
        untrusted.create-file

        ## Rule
        Execute only the declared Skill.
        """
        try agentManifest.write(
            to: agents.appendingPathComponent("personal.untrusted.Agent.md"),
            atomically: true,
            encoding: .utf8
        )

        let eventLog = InMemoryEventLog()
        let root = try await M8CompositionRoot(
            eventLog: eventLog,
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy(),
            workspaceToolsEnabled: true
        )
        let result = try await root.runChatSkillIfMatched(
            goalStatement: "Tạo file workspace/blocked.md với nội dung: must not be written",
            agentID: "personal.untrusted"
        )
        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace/blocked.md").path))
        let events = try await eventLog.allEvents()
        #expect(!events.contains {
            $0.kind == .moduleInvoked && $0.payload["moduleID"] == "tool.workspace.write"
        })
    }

    @Test("User-edited Agent scope is preserved during workspace Skill installation")
    func userEditedAgentScopeIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agents = directory.appendingPathComponent("Agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let customAgent = """
        id: personal.default
        name: Personal Default Agent
        version: 1.0.0
        description: Custom user scope.
        ---
        ## Skills
        text.normalize

        ## Rule
        Keep the custom scope unchanged.
        """
        try customAgent.write(
            to: agents.appendingPathComponent("personal.default.Agent.md"),
            atomically: true,
            encoding: .utf8
        )
        let root = try await M8CompositionRoot(
            provider: DeterministicFakeProvider(),
            storeDirectoryURL: directory,
            policy: AllowPolicy()
        )
        let agent = try await root.loadAgent(id: "personal.default")
        #expect(agent.skillIDs.map(\.rawValue) == ["text.normalize"])
        #expect(agent.instructions == "Keep the custom scope unchanged.")
    }
}
