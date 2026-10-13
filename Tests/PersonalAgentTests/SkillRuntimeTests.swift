import XCTest
import PAKernel
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

    func testChatInputTextPreservesCreateFileCommandGrammar() {
        let vietnamese = "Tạo file workspace/notes.md với nội dung: Nội dung đã ghi thật"
        XCTAssertEqual(SkillRuntime.chatInputText(from: vietnamese), vietnamese)
        let english = "Create file workspace/english.md with content: English file"
        XCTAssertEqual(SkillRuntime.chatInputText(from: english), english)
    }

    func testChatInputTextStillExtractsOrdinaryColonDelimitedPayload() {
        XCTAssertEqual(SkillRuntime.chatInputText(from: "Summarize this: actual text"), "actual text")
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

private struct FixedOutputSkillExecutor: SkillExecutor {
    let output: String
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String { output }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool { outputJSON == output }
}

extension SkillRuntimeTests {
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
