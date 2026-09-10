import Foundation
import Testing
import PAFoundation
import PASecurity
import PAStorage
import PAMemory
import PAProviders
import PAProvidersGrok
import PAProvidersOpenAI
import PAProvidersOpenAICompatible
import PAProvidersLocal
import PAPolicy
import PATools
import PAModules
import PASkills
import PAKernel
import PAComposition
import PAArchitecture
import PAObservability

@Suite("Contract surfaces compile and stay honest")
struct ContractSurfaceTests {
    @Test func skillManifestRequiresFullSurface() {
        let skill = SkillManifest(
            id: SkillID(rawValue: "demo.echo"),
            name: "Echo",
            description: "Contract fixture",
            version: SemanticVersion(major: 0, minor: 0, patch: 1),
            instructions: "Do not execute in M0",
            inputSchema: SchemaDocument(identifier: "echo.input"),
            outputSchema: SchemaDocument(identifier: "echo.output"),
            requiredCapabilities: .read,
            tools: [],
            dependencies: [],
            metadata: ["milestone": "M0"]
        )
        #expect(skill.id.rawValue == "demo.echo")
        #expect(skill.instructions.isEmpty == false)
    }

    @Test func moduleContractSupportsAtomicAndMeso() {
        let atomic = ModuleContract(
            id: ModuleID(rawValue: "mod.atomic"),
            name: "Atomic",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            kind: .atomic,
            capabilities: .read,
            inputSchema: SchemaDocument(identifier: "in"),
            outputSchema: SchemaDocument(identifier: "out")
        )
        #expect(atomic.kind == .atomic)
        #expect(ModuleKind.meso != atomic.kind)
    }

    @Test func memoryKindsAndLifecycleAreComplete() {
        #expect(MemoryKind.allCases.count == 10)
        #expect(MemoryLifecycleStage.allCases.map(\.rawValue).first == "capture")
        #expect(MemoryLifecycleStage.allCases.map(\.rawValue).last == "forget")
    }

    @Test func reservedProvidersLandInM2WithoutLiveVerification() {
        #expect(GrokProviderBoundary.availableInMilestone == "M2")
        #expect(OpenAIProviderBoundary.availableInMilestone == "M2")
        #expect(OpenAICompatibleProviderBoundary.availableInMilestone == "M2")
        #expect(LocalProviderBoundary.availableInMilestone == "M2")
        #expect(GrokProviderBoundary.liveNetworkVerified == false)
        #expect(OpenAIProviderBoundary.liveNetworkVerified == false)
        #expect(OpenAICompatibleProviderBoundary.liveNetworkVerified == false)
        #expect(LocalProviderBoundary.liveNetworkVerified == false)
        #expect(LocalProviderBoundary.intendedCompatibleServers.contains("ollama"))
    }

    @Test func policyDeniesByDefaultForDestructive() async {
        let policy = DenyDestructivePolicy()
        let read = await policy.evaluate(
            ActionIntent(capabilities: .read, summary: "read memory")
        )
        let destroy = await policy.evaluate(
            ActionIntent(capabilities: .destructive, summary: "wipe")
        )
        #expect(read.allowed)
        #expect(!destroy.allowed)
        #expect(destroy.requiresApproval)
    }

    @Test func compositionRootDoesNotExposeAFakeRuntime() {
        let root = M0CompositionRoot()
        #expect(root.milestone.milestone == "M0")
        #expect(root.milestone.kernelRuntime == false)
    }

    @Test func providerProtocolIsSatisfiableWithoutNetwork() async throws {
        let provider = UnavailableProvider()
        #expect(provider.capabilities.contains(.streaming))
        await #expect(throws: ProviderRuntimeError.unavailable) {
            _ = try await provider.complete(
                LLMRequest(model: ModelID(rawValue: "none"), prompt: "ping")
            )
        }
    }

    @Test func secretRefIsOutsideAgentState() {
        let identity = AgentIdentity(displayName: "Personal")
        let state = AgentState(identity: identity)
        let ref = ProviderCredentialRef(
            providerID: ProviderID(rawValue: "grok"),
            account: "grok.api"
        )
        #expect(state.activeGoalID == nil)
        #expect(ref.account == "grok.api")
    }

    @Test func storageConflictPolicyExists() {
        #expect(StorageBoundary.forbidsOverwriteWithoutConflictPolicy)
        let values = [
            ConflictResolution.keepLocal,
            .keepRemote,
            .merge,
            .requireUser,
        ]
        #expect(Set(values.map(\.rawValue)).count == 4)
    }
}

private struct DenyDestructivePolicy: PolicyEvaluating {
    func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        if intent.capabilities.contains(.destructive) {
            return .approve("destructive requires user approval")
        }
        return .allow()
    }
}

private struct UnavailableProvider: LLMProvider {
    let identity = ProviderIdentity(
        id: ProviderID(rawValue: "test.unavailable"),
        displayName: "Unavailable",
        models: []
    )
    let capabilities: ProviderCapabilities = [.streaming, .structuredOutput, .toolCalling]
    var health: ProviderHealth { get async { .unavailable } }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw ProviderRuntimeError.unavailable
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProviderRuntimeError.unavailable)
        }
    }
}
