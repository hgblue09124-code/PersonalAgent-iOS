import Foundation
import Testing
import PAKernel
import PAMemory
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
        let items = result.output.value(for: "items") ?? ""
        #expect(items.contains("prefer concise answers"))
        #expect(result.output.value(for: "status") == "retrieved")
    }
}
