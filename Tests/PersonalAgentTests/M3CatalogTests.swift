import Testing
import PAFoundation
import PAModules

@Suite("M3 module catalog")
struct M3CatalogTests {
    @Test func duplicateRegistrationRejected() async throws {
        let catalog = ModuleCatalog()
        try await catalog.register(EchoModule())
        await #expect(throws: ModuleRuntimeError.duplicateRegistration(DeterministicModuleIDs.echo)) {
            try await catalog.register(EchoModule())
        }
    }

    @Test func lookupIsDeterministic() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule(), FailingModule()])
        let ids = await catalog.contracts().map(\.id.rawValue)
        #expect(ids == ["mod.echo", "mod.fail"])
        #expect(await catalog.resolve(DeterministicModuleIDs.echo) != nil)
        #expect(await catalog.resolve(ModuleID(rawValue: "nope")) == nil)
    }

    @Test func initRejectsDuplicateBatch() {
        #expect(throws: ModuleRuntimeError.duplicateRegistration(DeterministicModuleIDs.echo)) {
            _ = try ModuleCatalog(modules: [EchoModule(), EchoModule()])
        }
    }

    @Test func contractsExposeCapabilityAndVersionMetadata() async throws {
        let catalog = try ModuleCatalog(modules: [EchoModule(), PrivilegedModule()])
        let contracts = await catalog.contracts()
        let echo = contracts.first { $0.id == DeterministicModuleIDs.echo }
        let privileged = contracts.first { $0.id == DeterministicModuleIDs.privileged }
        #expect(echo?.version == SemanticVersion(major: 0, minor: 1, patch: 0))
        #expect(echo?.capabilities.contains(.execute) == true)
        #expect(privileged?.capabilities.contains(.destructive) == true)
    }
}
