import XCTest
import PAKernel
@testable import PASkills

final class SkillRuntimeTests: XCTestCase {
    func testSkillRunsThroughNamedModule() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill], modules: ["calculator": { input in input == "187 * 43" ? "8041" : "0" }])
        let result = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "calculator", input: "187 * 43"))
        XCTAssertEqual(result, "8041")
    }

    func testMissingModuleFailsClosed() async throws {
        let skill = SkillDefinition(identity: "calculator", scope: "arithmetic", input: "expression", rule: "evaluate", output: "integer", permissions: ["MODEL_ACCESS"], dependencies: ["calculator"], version: "1")
        let runtime = SkillRuntime(skills: [skill])
        do {
            _ = try await runtime.run(SkillExecutionRequest(skillID: "calculator", moduleID: "missing", input: "1 + 1"))
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
