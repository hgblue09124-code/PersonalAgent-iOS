import XCTest
import PAKernel
import PAModules
@testable import PASkills

final class SkillRuntimeTests: XCTestCase {
    func testTextNormalizeRejectsUndeclaredInputFields() async throws {
        do {
            _ = try await SkillRuntime().execute(
                id: SkillRuntime.normalizationManifest.id,
                inputJSON: #"{"text":"ok","unexpected":"field"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("Undeclared input fields must fail closed")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
        }
    }

    func testTextNormalizeVerificationRejectsUndeclaredOutputFields() async throws {
        let verified = try await SkillRuntime().verify(
            id: SkillRuntime.normalizationManifest.id,
            outputJSON: #"{"text":"ok","unexpected":"field"}"#
        )
        XCTAssertFalse(verified)
    }

    func testUnsupportedManifestIsReportedUnavailableWithoutExecuting() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "custom.unsupported"),
            name: "Unsupported Skill",
            description: "A manifest with no registered executor.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Do not execute.",
            inputSchema: SchemaDocument(identifier: "custom.unsupported.input"),
            outputSchema: SchemaDocument(identifier: "custom.unsupported.output"),
            requiredCapabilities: [.read]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        let availability = await runtime.executorAvailability(for: manifest.id)
        XCTAssertEqual(availability, .unavailable)
    }

    func testExplicitlyRegisteredExecutorIsReportedAvailable() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "custom.registered"),
            name: "Registered Skill",
            description: "A Skill with an explicitly registered executor.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Run through the host executor.",
            inputSchema: SchemaDocument(identifier: "custom.registered.input"),
            outputSchema: SchemaDocument(identifier: "custom.registered.output"),
            requiredCapabilities: [.read]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(FixedOutputSkillExecutor(output: "trusted"), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)
        let availability = await runtime.executorAvailability(for: manifest.id)
        XCTAssertEqual(availability, .available)
    }

    func testChatInputTextPreservesCreateFileCommandGrammar() {
        let vietnamese = "Tạo file workspace/notes.md với nội dung: Nội dung đã ghi thật"
        XCTAssertEqual(SkillRuntime.chatInputText(from: vietnamese), vietnamese)
        let english = "Create file workspace/english.md with content: English file"
        XCTAssertEqual(SkillRuntime.chatInputText(from: english), english)
    }

    func testVietnameseWorkspaceRequestsSelectTheMatchingBuiltInSkill() async throws {
        let manifests = [
            SkillManifest(
                id: SkillID(rawValue: "workspace.search"),
                name: "Workspace Search",
                description: "Search workspace files by query.",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                instructions: "Search workspace files.",
                inputSchema: SchemaDocument(identifier: "search.input"),
                outputSchema: SchemaDocument(identifier: "search.output"),
                requiredCapabilities: [.read]
            ),
            SkillManifest(
                id: SkillID(rawValue: "workspace.read-file"),
                name: "Workspace Read File",
                description: "Read a file from the workspace.",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                instructions: "Read workspace files.",
                inputSchema: SchemaDocument(identifier: "read.input"),
                outputSchema: SchemaDocument(identifier: "read.output"),
                requiredCapabilities: [.read]
            ),
            SkillManifest(
                id: SkillID(rawValue: "workspace.create-file"),
                name: "Create File",
                description: "Create a new workspace file.",
                version: SemanticVersion(major: 1, minor: 0, patch: 0),
                instructions: "Create workspace files.",
                inputSchema: SchemaDocument(identifier: "create.input"),
                outputSchema: SchemaDocument(identifier: "create.output"),
                requiredCapabilities: [.write]
            )
        ]
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: manifests))

        let search = try await runtime.select(goalStatement: "Hãy tìm kiếm trong workspace các ghi chú")
        let read = try await runtime.select(goalStatement: "Vui lòng đọc file workspace/notes.md")
        let create = try await runtime.select(goalStatement: "Hãy tạo file workspace/notes.md với nội dung: Xin chào")

        XCTAssertEqual(search.rawValue, "workspace.search")
        XCTAssertEqual(read.rawValue, "workspace.read-file")
        XCTAssertEqual(create.rawValue, "workspace.create-file")
    }

    func testChatInputTextStillExtractsOrdinaryColonDelimitedPayload() {
        XCTAssertEqual(SkillRuntime.chatInputText(from: "Summarize this: actual text"), "actual text")
        XCTAssertEqual(SkillRuntime.chatInputText(from: "Summarize this: actual text  "), "actual text  ")
    }

    func testSkillRunsThroughNamedModule() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { input in input == "187 * 43" ? "8041" : "0" }])
        let result = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "calculator", input: "187 * 43"), policy: AllowSkillExecutionPolicy())
        XCTAssertEqual(result, "8041")
    }

    func testMissingModuleFailsClosed() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill])
        do {
            _ = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "missing", input: "1 + 1"), policy: AllowSkillExecutionPolicy())
            XCTFail("missing module must fail")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .missingModule("missing"))
        }
    }
    func testDuplicateSkillIdentityKeepsFirstDefinitionWithoutTrapping() async throws {
        let first = SkillDefinition(identity: "duplicate", scope: "first scope", input: "input", rule: "first rule", output: "output", permissions: [], dependencies: [], version: "1")
        let second = SkillDefinition(identity: "duplicate", scope: "second scope", input: "input", rule: "second rule", output: "output", permissions: [], dependencies: [], version: "2")

        let runtime = SkillRuntime(skills: [first, second])
        let discovered = try await runtime.discover(query: "")

        XCTAssertEqual(discovered.filter { $0.id.rawValue == "duplicate" }.count, 1)
        XCTAssertEqual(discovered.first(where: { $0.id.rawValue == "duplicate" })?.description, "first scope")
    }

    func testDuplicateManifestIdentityDoesNotTrapStoreInitialization() async throws {
        let manifest = SkillRuntime.normalizationManifest
        let store = InMemorySkillStore(manifests: [manifest, manifest])

        let discovered = try await store.discover(query: "")

        XCTAssertEqual(discovered.filter { $0.id == manifest.id }.count, 1)
    }

}

private actor ModuleInvocationCounter {
    private var invocations = 0
    func increment() { invocations += 1 }
    func value() -> Int { invocations }
}

private struct InvocationCountingModule: Module {
    let contract: ModuleContract
    let counter: ModuleInvocationCounter
    let outputJSON: String

    init(contract: ModuleContract, counter: ModuleInvocationCounter, outputJSON: String = "executed") {
        self.contract = contract
        self.counter = counter
        self.outputJSON = outputJSON
    }

    func execute(_ input: ModulePayload) async throws -> ModulePayload {
        await counter.increment()
        return ModulePayload(schema: contract.outputSchema, fields: ["output": outputJSON])
    }
}

private struct FixedOutputSkillExecutor: SkillExecutor {
    let output: String
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String { output }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool { outputJSON == output }
}

extension SkillRuntimeTests {
    func testModuleIDAloneCannotAuthorizeArbitraryInstalledSkill() async throws {
        let counter = ModuleInvocationCounter()
        let inputSchema = SchemaDocument(identifier: "test.raw-module.input")
        let outputSchema = SchemaDocument(identifier: "test.raw-module.output")
        let contract = ModuleContract(
            id: ModuleID(rawValue: "test.raw-module"),
            name: "Test raw module",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .atomic,
            capabilities: .execute,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredFields: ["arguments"]
        )
        let module = InvocationCountingModule(contract: contract, counter: counter)
        let catalog = try ModuleCatalog(modules: [module])
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.execute],
            policy: AllowSkillExecutionPolicy()
        )
        let manifest = SkillManifest(
            id: SkillID(rawValue: "untrusted.raw-module"),
            name: "Untrusted raw module",
            description: "Attempts to forward arbitrary arguments to a registered module.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Run arbitrary module arguments.",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredCapabilities: [.execute],
            metadata: ["moduleID": "test.raw-module"]
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"arguments":"must-not-run"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("A moduleID without an exact allowlisted Skill adapter must not authorize execution")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(manifest.id))
        }
        let invocationCount = await counter.value()
        XCTAssertEqual(invocationCount, 0)
    }

    func testBuiltInSkillCannotBindToDifferentModuleID() async throws {
        let counter = ModuleInvocationCounter()
        let inputSchema = SchemaDocument(identifier: "tool.workspace.read.input")
        let outputSchema = SchemaDocument(identifier: "tool.workspace.read.output")
        let contract = ModuleContract(
            id: ModuleID(rawValue: "tool.workspace.read"),
            name: "Test workspace read module",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .atomic,
            capabilities: .read,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredFields: ["arguments"]
        )
        let catalog = try ModuleCatalog(modules: [
            InvocationCountingModule(contract: contract, counter: counter)
        ])
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read],
            policy: AllowSkillExecutionPolicy()
        )
        let manifest = SkillManifest(
            id: SkillID(rawValue: "workspace.create-file"),
            name: "Tạo File",
            description: "Attempts to bind file creation to the read module.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Create a file.",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredCapabilities: [.read],
            metadata: [
                "moduleID": "tool.workspace.read",
                "chatInputAdapter": "workspace.create-file"
            ]
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"text":"Tạo file workspace/blocked.md với nội dung: must not run"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("A built-in Skill must not bind to a different module ID")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(manifest.id))
        }
        let invocationCount = await counter.value()
        XCTAssertEqual(invocationCount, 0)
    }

    func testCreateFileAdapterRejectsOutputWithoutReadbackVerification() async throws {
        let counter = ModuleInvocationCounter()
        let inputSchema = SchemaDocument(identifier: "tool.workspace.write.input")
        let outputSchema = SchemaDocument(identifier: "tool.workspace.write.output")
        let contract = ModuleContract(
            id: ModuleID(rawValue: "tool.workspace.write"),
            name: "Test workspace write module",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .atomic,
            capabilities: .write,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredFields: ["arguments"]
        )
        let forgedResult = #"{"operation":"write","path":"workspace/blocked.md","bytes":2,"verified":false}"#
        let catalog = try ModuleCatalog(modules: [
            InvocationCountingModule(contract: contract, counter: counter, outputJSON: forgedResult)
        ])
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.write],
            policy: AllowSkillExecutionPolicy()
        )
        let manifest = SkillManifest(
            id: SkillID(rawValue: "workspace.create-file"),
            name: "Tạo File",
            description: "Creates a workspace file.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Create a file and verify read-back.",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredCapabilities: [.write],
            metadata: ["moduleID": "tool.workspace.write", "chatInputAdapter": "workspace.create-file"]
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"text":"Tạo file workspace/blocked.md với nội dung: hi"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("A write result without read-back verification must not be accepted")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .verificationFailed(manifest.id))
        }
    }

    func testSearchAdapterRejectsUnsafeMatchPaths() async throws {
        let counter = ModuleInvocationCounter()
        let inputSchema = SchemaDocument(identifier: "tool.workspace.read.input")
        let outputSchema = SchemaDocument(identifier: "tool.workspace.read.output")
        let contract = ModuleContract(
            id: ModuleID(rawValue: "tool.workspace.read"),
            name: "Test workspace read module",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            kind: .atomic,
            capabilities: .read,
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredFields: ["arguments"]
        )
        let forgedResult = #"{"operation":"search","query":"needle","matches":["../secrets.txt"],"visited":1,"truncated":false}"#
        let catalog = try ModuleCatalog(modules: [
            InvocationCountingModule(contract: contract, counter: counter, outputJSON: forgedResult)
        ])
        let moduleRuntime = ModuleRuntime(
            catalog: catalog,
            grantedCapabilities: [.read],
            policy: AllowSkillExecutionPolicy()
        )
        let manifest = SkillManifest(
            id: SkillID(rawValue: "workspace.search"),
            name: "Workspace Search",
            description: "Searches workspace text.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Search workspace text.",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            requiredCapabilities: [.read],
            metadata: ["moduleID": "tool.workspace.read", "chatInputAdapter": "workspace.search"]
        )
        let runtime = SkillRuntime(
            store: InMemorySkillStore(manifests: [manifest]),
            moduleRuntime: moduleRuntime
        )

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"text":"Search workspace for needle"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("Search results containing an unsafe path must not be accepted as verified")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .verificationFailed(manifest.id))
        }
    }

    func testExecutorMetadataCannotGrantNormalizationToAnotherSkillID() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "untrusted.normalize"),
            name: "Untrusted normalization",
            description: "Attempts to select a built-in executor through metadata.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Normalize text.",
            inputSchema: SkillRuntime.normalizationManifest.inputSchema,
            outputSchema: SkillRuntime.normalizationManifest.outputSchema,
            requiredCapabilities: SkillRuntime.normalizationManifest.requiredCapabilities,
            metadata: ["executor": "text.normalize"]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"text":"  must-not-normalize  "}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("Executor metadata must not grant a built-in executor to another Skill ID")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(manifest.id))
        }
    }

    func testExplicitlyRegisteredCustomExecutorStillExecutesAndVerifies() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "custom.explicit"),
            name: "Explicit custom executor",
            description: "Uses a trusted executor registered by the host.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return trusted output.",
            inputSchema: SchemaDocument(identifier: "custom.explicit.input"),
            outputSchema: SchemaDocument(identifier: "custom.explicit.output"),
            requiredCapabilities: [.execute]
        )
        let registry = SkillExecutorRegistry()
        await registry.register(FixedOutputSkillExecutor(output: "trusted"), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        let output = try await runtime.executeVerified(
            id: manifest.id,
            inputJSON: #"{"input":"ignored-by-test-executor"}"#,
            policy: AllowSkillExecutionPolicy()
        )
        XCTAssertEqual(output, "trusted")
    }

    func testExecutorRegistryDoesNotAllowSilentReplacement() async throws {
        let registry = SkillExecutorRegistry()
        await registry.register(FixedOutputSkillExecutor(output: "trusted"), for: "custom.skill")
        await registry.register(FixedOutputSkillExecutor(output: "replacement"), for: "custom.skill")

        let registered = await registry.executor(for: "custom.skill")
        let executor = try XCTUnwrap(registered)
        let output = try await executor.execute(
            manifest: SkillRuntime.normalizationManifest,
            inputJSON: #"{"text":"test"}"#
        )
        XCTAssertEqual(output, "trusted")
    }

    func testVerificationDoesNotBorrowNormalizationManifestForUnknownSkill() async throws {
        let registry = SkillExecutorRegistry()
        await registry.register(FixedOutputSkillExecutor(output: "accepted"), for: "unlisted.skill")
        let runtime = SkillRuntime(executors: registry)

        do {
            _ = try await runtime.verify(id: SkillID(rawValue: "unlisted.skill"), outputJSON: "accepted")
            XCTFail("Unknown Skill must not be verified using a different manifest")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(SkillID(rawValue: "unlisted.skill")))
        }
    }
}


private struct AllowSkillExecutionPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("test-only explicit grant") }
}
private struct DenySkillExecutionPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .deny("test denial") }
}
extension SkillRuntimeTests {
    func testLegacySkillRunFailsClosedWithoutExplicitPolicy() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: [], dependencies: [], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { _ in "should not run" }])
        do {
            _ = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "calculator", input: "1 + 1"))
            XCTFail("Execution without an explicit policy must fail closed")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .policyDenied("explicit policy required"))
        }
    }

    func testSkillRunRespectsDeniedPolicy() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: [], dependencies: [], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { _ in "should not run" }])
        do {
            _ = try await runtime.run(
                SkillExecutionRequest(skillID: "calculator", moduleID: "calculator", input: "1 + 1"),
                policy: DenySkillExecutionPolicy()
            )
            XCTFail("Denied policy must prevent execution")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .policyDenied("test denial"))
        }
    }
}


private struct RejectingVerifierExecutor: SkillExecutor {
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        #"{"result":"unverified"}"#
    }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        false
    }
}

extension SkillRuntimeTests {
    func testStandaloneVerificationHonorsExistingTaskCancellation() async throws {
        let runtime = SkillRuntime()
        let task = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runtime.verify(
                id: SkillRuntime.normalizationManifest.id,
                outputJSON: #"{"text":"ok"}"#
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled verification must not return a result")
        } catch is CancellationError {
            // Expected: cancellation is observed at the verification boundary.
        }
    }

    func testExecuteVerifiedRejectsOutputWhenExecutorVerificationFails() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "test.rejecting-verifier"),
            name: "Rejecting verifier",
            description: "Test executor that rejects its own output",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Return output that does not verify.",
            inputSchema: SchemaDocument(identifier: "test.input"),
            outputSchema: SchemaDocument(identifier: "test.output"),
            requiredCapabilities: [.execute]
        )
        let store = InMemorySkillStore(manifests: [manifest])
        let registry = SkillExecutorRegistry()
        await registry.register(RejectingVerifierExecutor(), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: store, executors: registry)

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"input":"test"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("An output rejected by its executor must not be returned as verified")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .verificationFailed(manifest.id))
        }
    }
}


extension SkillRuntimeTests {
    func testNormalizationExecutorRejectsManifestWithMismatchedSchemas() async throws {
        let mismatched = SkillManifest(
            id: SkillRuntime.normalizationManifest.id,
            name: SkillRuntime.normalizationManifest.name,
            description: SkillRuntime.normalizationManifest.description,
            version: SkillRuntime.normalizationManifest.version,
            instructions: SkillRuntime.normalizationManifest.instructions,
            inputSchema: SchemaDocument(identifier: "unrelated.input"),
            outputSchema: SchemaDocument(identifier: "unrelated.output"),
            requiredCapabilities: SkillRuntime.normalizationManifest.requiredCapabilities
        )
        let executor = TextNormalizeSkillExecutor()

        do {
            _ = try await executor.execute(manifest: mismatched, inputJSON: #"{"text":"ok"}"#)
            XCTFail("Normalization executor must not run against a different schema contract")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
        }

        let verified = try await executor.verify(manifest: mismatched, outputJSON: #"{"text":"ok"}"#)
        XCTAssertFalse(verified, "A different manifest schema must not verify as text.normalize")
    }
}


extension SkillRuntimeTests {
    func testExecuteVerifiedStillEnforcesDeniedPolicy() async throws {
        do {
            _ = try await SkillRuntime().executeVerified(
                id: SkillRuntime.normalizationManifest.id,
                inputJSON: #"{"text":"must not execute"}"#,
                policy: DenySkillExecutionPolicy()
            )
            XCTFail("Verified execution must not bypass a denied policy")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .policyDenied("test denial"))
        }
    }
}


private struct MismatchedIdentitySkillStore: SkillStore {
    let manifest: SkillManifest

    func discover(query: String) async throws -> [SkillManifest] {
        [manifest]
    }

    func load(id: SkillID) async throws -> SkillManifest {
        manifest
    }
}

extension SkillRuntimeTests {
    func testExecutionRejectsStoreManifestWithDifferentIdentity() async throws {
        let requestedID = SkillID(rawValue: "requested.skill")
        let runtime = SkillRuntime(store: MismatchedIdentitySkillStore(
            manifest: SkillRuntime.normalizationManifest
        ))

        do {
            _ = try await runtime.execute(
                id: requestedID,
                inputJSON: #"{"text":"must not execute"}"#,
                policy: AllowSkillExecutionPolicy()
            )
            XCTFail("A store must not substitute a different Skill manifest")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(requestedID))
        }
    }

    func testVerificationRejectsStoreManifestWithDifferentIdentity() async throws {
        let requestedID = SkillID(rawValue: "requested.skill")
        let runtime = SkillRuntime(store: MismatchedIdentitySkillStore(
            manifest: SkillRuntime.normalizationManifest
        ))

        do {
            _ = try await runtime.verify(
                id: requestedID,
                outputJSON: #"{"text":"already normalized"}"#
            )
            XCTFail("A store must not verify output against another Skill's manifest")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .unknownSkill(requestedID))
        }
    }
}


extension SkillRuntimeTests {
    func testExactNameAmbiguityFailsClosed() async throws {
        let first = SkillManifest(
            id: SkillID(rawValue: "workspace.search"),
            name: "Workspace Search",
            description: "Search workspace files",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Search workspace files.",
            inputSchema: SchemaDocument(identifier: "workspace.search.input"),
            outputSchema: SchemaDocument(identifier: "workspace.search.output"),
            requiredCapabilities: [.read]
        )
        let second = SkillManifest(
            id: SkillID(rawValue: "document.search"),
            name: "Workspace Search",
            description: "Search document files",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Search document files.",
            inputSchema: SchemaDocument(identifier: "document.search.input"),
            outputSchema: SchemaDocument(identifier: "document.search.output"),
            requiredCapabilities: [.read]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))

        do {
            _ = try await runtime.select(goalStatement: "Workspace Search")
            XCTFail("Ambiguous exact Skill names must not select an arbitrary capability")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }
}


extension SkillRuntimeTests {
    private func selectionManifest(id: String, name: String, description: String) -> SkillManifest {
        SkillManifest(
            id: SkillID(rawValue: id),
            name: name,
            description: description,
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Perform \(name).",
            inputSchema: SchemaDocument(identifier: "\(id).input"),
            outputSchema: SchemaDocument(identifier: "\(id).output"),
            requiredCapabilities: [.read]
        )
    }

    func testAllowedSkillScopeIsAppliedBeforeAmbiguityResolution() async throws {
        let first = selectionManifest(
            id: "workspace.search",
            name: "Workspace Search",
            description: "Search workspace files"
        )
        let second = selectionManifest(
            id: "document.search",
            name: "Workspace Search",
            description: "Search document files"
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))

        let selected = try await runtime.select(
            goalStatement: "Workspace Search",
            allowedSkillIDs: [first.id]
        )

        XCTAssertEqual(selected, first.id)
    }

    func testEqualPartialNameMatchesFailClosed() async throws {
        let first = selectionManifest(
            id: "workspace.search",
            name: "Workspace Search",
            description: "Search workspace files"
        )
        let second = selectionManifest(
            id: "document.search",
            name: "Document Search",
            description: "Search document files"
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))

        do {
            _ = try await runtime.select(goalStatement: "search workspace document")
            XCTFail("Equally matching Skill names must not be resolved by identifier ordering")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }
}
