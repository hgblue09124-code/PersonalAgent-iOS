import Foundation
import Testing
import PAKernel
import PAMemory
import PAModules
import PASkills

@Suite("Memory Skill")
struct MemorySkillTests {
    @Test func captureAndRetrieveConversation() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)
        let skill = MemorySkillModule(memory: runtime)
        let schema = skill.contract.inputSchema
        _ = try await skill.execute(ModulePayload(schema: schema, fields: [
            "action": "capture", "conversationID": "conversation-test",
            "role": "user", "content": "Remember that I prefer concise answers."
        ]))
        let result = try await skill.execute(ModulePayload(schema: schema, fields: [
            "action": "retrieve", "conversationID": "conversation-test", "limit": "10"
        ]))
        let items = result.value(for: "items") ?? ""
        #expect(items.contains("prefer concise answers"))
        #expect(result.value(for: "status") == "retrieved")
    }

    @Test func skillCatalogInvokesRegisteredModule() async throws {
        let store = InMemoryMemoryStore()
        let memoryRuntime = MemoryRuntime(store: store)
        let module = MemorySkillModule(memory: memoryRuntime)

        let moduleCatalog = try ModuleCatalog(modules: [module])
        let moduleRuntime = ModuleRuntime(
            catalog: moduleCatalog,
            grantedCapabilities: [.read, .write, .execute]
        )

        var skillCatalog = SkillCatalog()
        skillCatalog.register(MemorySkillModule.self)
        let invoker = SkillInvoker(catalog: skillCatalog, moduleRuntime: moduleRuntime)

        let result = try await invoker.execute(
            skillID: "skill.memory",
            input: ModulePayload(schema: module.contract.inputSchema, fields: [
                "action": "capture",
                "conversationID": "invocation-test",
                "role": "user",
                "content": "Skill invocation works."
            ])
        )

        #expect(result.moduleID == MemorySkillModule.id)
        #expect(result.output.value(for: "status") == "captured")
    }
}
