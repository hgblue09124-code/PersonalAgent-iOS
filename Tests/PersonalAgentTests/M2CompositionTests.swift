import Testing
import PAFoundation
import PAArchitecture
import PAComposition
import PAKernel
import PAProviders

@Suite("M2 composition")
struct M2CompositionTests {
    @Test func rootWiresKernelAndProviderWithoutNetwork() async {
        let root = await M2CompositionRoot(
            identity: AgentIdentity(id: AgentID(rawValue: "m2"), displayName: "Personal")
        )
        #expect(root.milestone == .m2)
        #expect(root.milestone.providers)
        #expect(root.milestone.kernelRuntime)
        let state = await root.runtime.currentState()
        #expect(state.lifecycle == .created)
        #expect(await root.runtime.coordination.isWiredForProvider)
        #expect(await root.providerRuntime.lifecycle == .ready)
        #expect(root.catalog.resolve(ProviderID(rawValue: "fake")) != nil)
    }

    @Test func m1RootRemainsAvailable() async {
        let root = await M1CompositionRoot()
        #expect(root.milestone == .m1)
        #expect(root.milestone.providers == false)
    }
}
