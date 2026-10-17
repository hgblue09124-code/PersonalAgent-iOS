import XCTest
import PAKernel
@testable import PASkills

final class SkillInputSchemaValidationTests: XCTestCase {
    func testInvalidInputFailsBeforeCustomExecutorRuns() async throws {
        let counter = SkillExecutionCounter()
        let manifest = makeManifest(schema: #"{"type":"object","required":["name"],"properties":{"name":{"type":"string"}},"additionalProperties":false}"#)
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        for input in [#"{"unexpected":"value"}"#, #"{"name":42}"#] {
            do {
                _ = try await runtime.execute(
                    id: manifest.id,
                    inputJSON: input,
                    policy: AllowInputSchemaTestPolicy()
                )
                XCTFail("Missing required fields, wrong types, and undeclared keys must fail closed")
            } catch {
                XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
            }
        }
        let executions = await counter.count()
        XCTAssertEqual(executions, 0)
    }

    func testValidInputMatchesManifestSchemaAndExecutes() async throws {
        let counter = SkillExecutionCounter()
        let manifest = makeManifest(schema: #"{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":1}},"additionalProperties":false}"#)
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        let output = try await runtime.execute(
            id: manifest.id,
            inputJSON: #"{"name":"Ada"}"#,
            policy: AllowInputSchemaTestPolicy()
        )
        XCTAssertEqual(output, #"{"ok":true}"#)
        let executions = await counter.count()
        XCTAssertEqual(executions, 1)
    }

    func testMalformedSchemaFailsClosedBeforeExecutorRuns() async throws {
        let counter = SkillExecutionCounter()
        let manifest = makeManifest(schema: #"{"type":"object","required":[}"#)
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        do {
            _ = try await runtime.execute(
                id: manifest.id,
                inputJSON: #"{"name":"Ada"}"#,
                policy: AllowInputSchemaTestPolicy()
            )
            XCTFail("Malformed manifest schemas must fail closed")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
        }
        let executions = await counter.count()
        XCTAssertEqual(executions, 0)
    }

    func testUnsupportedSchemaKeywordFailsClosedBeforeExecutorRuns() async throws {
        let counter = SkillExecutionCounter()
        let manifest = makeManifest(schema: #"{"type":"object","patternProperties":{".*":{"type":"string"}}}"#)
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        do {
            _ = try await runtime.execute(
                id: manifest.id,
                inputJSON: #"{"name":"Ada"}"#,
                policy: AllowInputSchemaTestPolicy()
            )
            XCTFail("Unsupported validation keywords must fail closed")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
        }
        let executions = await counter.count()
        XCTAssertEqual(executions, 0)
    }

    private func makeManifest(schema: String) -> SkillManifest {
        SkillManifest(
            id: SkillID(rawValue: "custom.schema-checked"),
            name: "Schema Checked",
            description: "A Skill whose input is validated by the runtime.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Accept a name.",
            inputSchema: SchemaDocument(identifier: "custom.schema-checked.input", rawJSON: schema),
            outputSchema: SchemaDocument(identifier: "custom.schema-checked.output"),
            requiredCapabilities: [.read, .execute]
        )
    }
}

private actor SkillExecutionCounter {
    private var executions = 0
    func increment() { executions += 1 }
    func count() -> Int { executions }
}

private struct CountingSkillExecutor: SkillExecutor {
    let counter: SkillExecutionCounter
    func execute(manifest: SkillManifest, inputJSON: String) async throws -> String {
        await counter.increment()
        return #"{"ok":true}"#
    }
    func verify(manifest: SkillManifest, outputJSON: String) async throws -> Bool {
        outputJSON == #"{"ok":true}"#
    }
}

private struct AllowInputSchemaTestPolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision { .allow("schema test grant") }
}
