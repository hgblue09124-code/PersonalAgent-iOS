import Testing
import PAFoundation
import PAModules
import PATools
import PASkills

@Suite("M3 module contract")
struct M3ContractTests {
    @Test func payloadIsSchemaTaggedStringMap() {
        let payload = ModulePayload(
            schema: SchemaDocument(identifier: "mod.echo.in"),
            fields: ["text": "hi"]
        )
        #expect(payload.value(for: "text") == "hi")
        #expect(payload.fields["text"] == "hi")
        #expect(payload.schema.identifier == "mod.echo.in")
    }

    @Test func toolAndSkillRemainDistinct() {
        let tool = EchoTool()
        #expect(tool.manifest.id.rawValue == "echo")
        #expect(SkillCompositionKind.atomicModule != SkillCompositionKind.skill)
        let wrapped = ToolModule(tool: tool)
        #expect(wrapped.contract.kind == .atomic)
        #expect(wrapped.contract.id.rawValue == "tool.echo")
    }

    @Test func moduleContractKeepsIdentityVersionAndSchemas() {
        let contract = EchoModule().contract
        #expect(contract.id == DeterministicModuleIDs.echo)
        #expect(contract.version.major == 0)
        #expect(contract.inputSchema.identifier == "mod.echo.in")
        #expect(contract.requiredFields == ["text"])
    }
}
