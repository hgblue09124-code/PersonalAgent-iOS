import XCTest
import PAKernel
@testable import PASkills

final class SkillIntentSelectionTests: XCTestCase {
    func testSelectsSkillByDescriptionWhenNameIsNotInRequest() async throws {
        let manifest = SkillManifest(
            id: SkillID(rawValue: "math.quick"),
            name: "Quick Math",
            description: "Calculate arithmetic equations and evaluate the equation.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Evaluate the supplied expression.",
            inputSchema: SchemaDocument(identifier: "math.in"),
            outputSchema: SchemaDocument(identifier: "math.out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [manifest]))
        let selected = try await runtime.select(goalStatement: "Please calculate this equation")
        XCTAssertEqual(selected, manifest.id)
    }

    func testAmbiguousDescriptionMatchFailsClosed() async throws {
        let first = SkillManifest(
            id: SkillID(rawValue: "document.summary"),
            name: "Document Summary",
            description: "Summarize documents and text.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied material.",
            inputSchema: SchemaDocument(identifier: "summary.in"),
            outputSchema: SchemaDocument(identifier: "summary.out"),
            requiredCapabilities: [.read, .execute]
        )
        let second = SkillManifest(
            id: SkillID(rawValue: "text.summary"),
            name: "Material Digest",
            description: "Summarize text and documents.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied material.",
            inputSchema: SchemaDocument(identifier: "text-summary.in"),
            outputSchema: SchemaDocument(identifier: "text-summary.out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))
        do {
            _ = try await runtime.select(goalStatement: "summarize this text")
            XCTFail("ambiguous skill intent must not select arbitrarily")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }
    
    func testAmbiguousNameMatchesFailClosed() async throws {
        let first = SkillManifest(
            id: SkillID(rawValue: "summary.first"),
            name: "Text Summary",
            description: "Summarize text content.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied text.",
            inputSchema: SchemaDocument(identifier: "summary.first.in"),
            outputSchema: SchemaDocument(identifier: "summary.first.out"),
            requiredCapabilities: [.read, .execute]
        )
        let second = SkillManifest(
            id: SkillID(rawValue: "summary.second"),
            name: "Text Summary",
            description: "Summarize text content.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied text.",
            inputSchema: SchemaDocument(identifier: "summary.second.in"),
            outputSchema: SchemaDocument(identifier: "summary.second.out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))
        do {
            _ = try await runtime.select(goalStatement: "please text summary")
            XCTFail("equally specific name matches must not select arbitrarily")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }

    
    func testDuplicateExactSkillNamesFailClosed() async throws {
        let first = SkillManifest(
            id: SkillID(rawValue: "summary.first"),
            name: "Text Summary",
            description: "Summarize text content.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied text.",
            inputSchema: SchemaDocument(identifier: "summary.first.in"),
            outputSchema: SchemaDocument(identifier: "summary.first.out"),
            requiredCapabilities: [.read, .execute]
        )
        let second = SkillManifest(
            id: SkillID(rawValue: "summary.second"),
            name: "Text Summary",
            description: "Summarize text content.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Summarize supplied text.",
            inputSchema: SchemaDocument(identifier: "summary.second.in"),
            outputSchema: SchemaDocument(identifier: "summary.second.out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(store: InMemorySkillStore(manifests: [first, second]))
        do {
            _ = try await runtime.select(goalStatement: "Text Summary")
            XCTFail("duplicate exact skill names must not choose the first manifest")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }

    func testDisabledStoredSkillIsExcludedFromSelection() async throws {
        let disabled = SkillManifest(
            id: SkillID(rawValue: "math.quick"),
            name: "Quick Math",
            description: "Calculate arithmetic expressions and evaluate equations.",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            instructions: "Evaluate the supplied expression.",
            inputSchema: SchemaDocument(identifier: "math.in"),
            outputSchema: SchemaDocument(identifier: "math.out"),
            requiredCapabilities: [.read, .execute]
        )
        let runtime = SkillRuntime(
            disabled: ["math.quick"],
            store: InMemorySkillStore(manifests: [disabled])
        )
        do {
            _ = try await runtime.select(goalStatement: "please calculate this equation")
            XCTFail("disabled skill must not be selected")
        } catch {
            XCTAssertEqual(error as? SkillExecutionError, .noSelection)
        }
    }
}
