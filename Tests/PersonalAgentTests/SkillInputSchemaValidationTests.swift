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

    func testMarkdownImportedSkillEnforcesStructuralInputAndOutputSchemas() async throws {
        let markdown = #"""
        id: custom.markdown-schema
        name: Markdown Schema
        version: 1.0.0
        description: Imported Skill with structural contracts.
        inputSchemaJSON: {"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":1}},"additionalProperties":false}
        outputSchemaJSON: {"type":"object","required":["ok"],"properties":{"ok":{"type":"boolean"}},"additionalProperties":false}
        ---
        ## Input
        custom.markdown-schema.input

        ## Output
        custom.markdown-schema.output

        ## Rule
        Accept a name and return a verified result.
        """#
        let manifest = try SkillMarkdownParser().parse(markdown)
        XCTAssertEqual(manifest.inputSchema.identifier, "custom.markdown-schema.input")
        XCTAssertEqual(manifest.outputSchema.identifier, "custom.markdown-schema.output")
        XCTAssertNotEqual(manifest.inputSchema.rawJSON, "{}")
        XCTAssertNotEqual(manifest.outputSchema.rawJSON, "{}")

        let counter = SkillExecutionCounter()
        let registry = SkillExecutorRegistry()
        await registry.register(CountingSkillExecutor(counter: counter), for: manifest.id.rawValue)
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]), executors: registry)

        do {
            _ = try await runtime.executeVerified(
                id: manifest.id,
                inputJSON: #"{"unexpected":true}"#,
                policy: AllowInputSchemaTestPolicy()
            )
            XCTFail("Imported structural input schema must reject undeclared properties")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .malformedSkill)
        }
        let rejectedExecutionCount = await counter.count()
        XCTAssertEqual(rejectedExecutionCount, 0)

        let output = try await runtime.executeVerified(
            id: manifest.id,
            inputJSON: #"{ "name":"Ada" }"#,
            policy: AllowInputSchemaTestPolicy()
        )
        XCTAssertEqual(output, #"{ "ok":true }"#)
        let successfulExecutionCount = await counter.count()
        XCTAssertEqual(successfulExecutionCount, 1)
    }

    func testMarkdownParserRejectsMalformedStructuralSchemaJSON() throws {
        let markdown = #"""
        id: custom.bad-schema
        name: Bad Schema
        version: 1.0.0
        inputSchemaJSON: {"type":
        ---
        ## Input
        custom.bad-schema.input

        ## Output
        custom.bad-schema.output

        ## Rule
        Reject malformed schema.
        """#
        XCTAssertThrowsError(try SkillMarkdownParser().parse(markdown)) { error in
            XCTAssertEqual(error as? SkillMarkdownError, .invalidSchema("invalid JSON object in inputSchemaJSON"))
        }
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
