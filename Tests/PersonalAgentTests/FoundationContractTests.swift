import Testing
import PAFoundation

@Suite("Foundation contracts")
struct FoundationContractTests {
    @Test func identifiersAreDistinctTypedValues() {
        let agent = AgentID(rawValue: "a")
        let goal = GoalID(rawValue: "a")
        #expect(agent.rawValue == goal.rawValue)
        #expect(AgentID().rawValue != AgentID().rawValue)
    }

    @Test func semanticVersionOrdersLexicallyByComponent() {
        let a = SemanticVersion(major: 1, minor: 2, patch: 0)
        let b = SemanticVersion(major: 1, minor: 10, patch: 0)
        #expect(a < b)
        #expect(a.description == "1.2.0")
    }

    @Test func capabilityLevelsDoNotCollapse() {
        #expect(CapabilityLevel.read != .write)
        #expect(CapabilityLevel.execute != .network)
        #expect(CapabilityLevel.destructive.requiresExplicitApproval)
        #expect(!CapabilityLevel.read.requiresExplicitApproval)
        let combo: CapabilityLevel = [.execute, .network]
        #expect(combo.requiresExplicitApproval)
    }

    @Test func agentPhaseCoversRequiredObservabilityStates() {
        let raw = Set(AgentPhase.allCases.map(\.rawValue))
        for required in [
            "idle", "thinking", "planning", "executing",
            "waitingForApproval", "syncing", "failed", "completed",
        ] {
            #expect(raw.contains(required))
        }
    }
}
