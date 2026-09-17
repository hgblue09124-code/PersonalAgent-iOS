import Testing
import PAFoundation
import PAArchitecture
import PAComposition
import PAKernel

@Suite("M1 composition")
struct M1CompositionTests {
    @Test func m1RootExposesLiveRuntimeNotAStub() async {
        let root = await M1CompositionRoot(
            identity: AgentIdentity(id: AgentID(rawValue: "comp"), displayName: "Personal")
        )
        #expect(root.milestone == .m1)
        #expect(root.milestone.kernelRuntime)
        let state = await root.runtime.currentState()
        #expect(state.lifecycle == .created)
        #expect(state.identity.displayName == "Personal")
    }

    @Test func m0RootRemainsHonestSkeleton() {
        let root = M0CompositionRoot()
        #expect(root.milestone == .m0)
        #expect(root.milestone.kernelRuntime == false)
    }
}
