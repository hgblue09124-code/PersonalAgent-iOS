import Testing
import PAKernel
import PASkills
import PAComposition

@Suite("Skill Runtime")
struct SkillRuntimeTests {
    @Test func discoverSelectExecuteAndVerify() async throws {
        let runtime = SkillRuntime()
        let discovered = try await runtime.discover(query: "normalize")
        #expect(discovered.map(\.id.rawValue) == ["text.normalize"])

        let selected = try await runtime.select(goalStatement: "normalize this text")
        #expect(selected.rawValue == "text.normalize")

        let output = try await runtime.execute(
            id: selected,
            inputJSON: "{\"text\":\"  hello agent  \"}",
            policy: DefaultPolicyEvaluator()
        )
        #expect(output.contains("hello agent"))
        #expect(try await runtime.verify(id: selected, outputJSON: output))
    }

    @Test func malformedInputFailsClosed() async throws {
        let runtime = SkillRuntime()
        await #expect(throws: SkillRuntimeError.invalidInput(.init(rawValue: "text.normalize"))) {
            try await runtime.execute(
                id: .init(rawValue: "text.normalize"),
                inputJSON: "{\"wrong\":true}",
                policy: AllowAllPolicy()
            )
        }
    }
}
