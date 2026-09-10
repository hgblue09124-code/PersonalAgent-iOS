import PAFoundation

/// Architecture encoded as data so tests can lock the skeleton without a runtime.
public enum ArchitectureManifest: Sendable {
    public static let contractFoundation = "M0"
    public static let milestone = "M3"
    public static let product = "PersonalAgent"
    public static let foundationVersion = SemanticVersion(major: 0, minor: 1, patch: 0)

    public static let axis: [String] = [
        "UI",
        "Composition",
        "Kernel",
        "Cognition/Agency/Policy/Memory",
        "Skills/Tools/Modules/Providers",
        "Storage/Sync",
        "Events/Observability/Security",
        "Foundation",
    ]

    public static let cognitionPipeline: [String] = CognitionPipelineOrder.stages
    public static let agencyLoop: [String] = AgencyLoopOrder.stages

    public static let forbiddenCompanionDependencies: [String] = [
        "agent-core",
        "agent-core-next",
        "living-data-ocean",
        "Firebase",
        "Supabase",
    ]

    public static let reservedProviderModules: [String] = [
        "PAProvidersGrok",
        "PAProvidersOpenAI",
        "PAProvidersOpenAICompatible",
        "PAProvidersLocal",
    ]

    public static let reservedProviderIDs: [(id: String, milestone: String)] = [
        ("grok", "M2"),
        ("openai", "M2"),
        ("openai-compatible", "M2"),
        ("local", "M2"),
    ]

    /// Target -> allowed imported PA* modules. Foundation is implicit for all.
    public static let allowedImports: [String: Set<String>] = [
        "PAFoundation": [],
        "PAObservability": ["PAFoundation"],
        "PAEvents": ["PAFoundation", "PAObservability"],
        "PASecurity": ["PAFoundation"],
        "PAStorage": ["PAFoundation", "PAEvents", "PAObservability"],
        "PAMemory": ["PAFoundation", "PAStorage", "PAEvents"],
        "PAProviders": ["PAFoundation", "PAObservability", "PASecurity", "PAEvents"],
        "PAProvidersGrok": ["PAProviders", "PAFoundation"],
        "PAProvidersOpenAI": ["PAProviders", "PAFoundation"],
        "PAProvidersOpenAICompatible": ["PAProviders", "PAFoundation"],
        "PAProvidersLocal": ["PAProviders", "PAFoundation"],
        "PAPolicy": ["PAFoundation"],
        "PATools": ["PAFoundation", "PAPolicy", "PAObservability"],
        "PAModules": ["PAFoundation", "PAPolicy", "PAObservability", "PAEvents"],
        "PASkills": ["PAFoundation", "PAModules", "PATools", "PAPolicy"],
        "PACognition": ["PAFoundation", "PAProviders", "PAMemory", "PASkills"],
        "PAAgency": ["PAFoundation", "PAPolicy", "PATools", "PACognition"],
        "PAKernel": [
            "PAFoundation",
            "PAPolicy",
            "PAAgency",
            "PACognition",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PAModules",
        ],
        "PAArchitecture": ["PAFoundation"],
        "PAComposition": [
            "PAFoundation",
            "PAArchitecture",
            "PAKernel",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PASecurity",
            "PAModules",
            "PASkills",
            "PATools",
        ],
    ]

    public static let kernelMustNotImport: Set<String> = [
        "PAProvidersGrok",
        "PAProvidersOpenAI",
        "PAProvidersOpenAICompatible",
        "PAProvidersLocal",
        "SwiftUI",
        "UIKit",
        "AppKit",
        "URLSession",
    ]
}

public enum CognitionPipelineOrder {
    public static let stages = [
        "perception",
        "context",
        "reasoning",
        "planning",
        "actionProposal",
        "verification",
        "reflection",
        "stateUpdate",
    ]
}

public enum AgencyLoopOrder {
    public static let stages = [
        "goal",
        "plan",
        "execute",
        "observe",
        "evaluate",
        "adapt",
        "continueOrCompleteOrAbort",
    ]
}

public struct MilestoneGate: Sendable, Equatable {
    public let milestone: String
    public let kernelRuntime: Bool
    public let providers: Bool
    public let storageEngine: Bool
    public let memoryEngine: Bool
    public let skillRuntime: Bool
    public let toolRuntime: Bool
    public let cognitionLoop: Bool
    public let eventReplay: Bool

    public static let m0 = MilestoneGate(
        milestone: "M0",
        kernelRuntime: false,
        providers: false,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m1 = MilestoneGate(
        milestone: "M1",
        kernelRuntime: true,
        providers: false,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m2 = MilestoneGate(
        milestone: "M2",
        kernelRuntime: true,
        providers: true,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: false,
        toolRuntime: false,
        cognitionLoop: false,
        eventReplay: false
    )

    public static let m3 = MilestoneGate(
        milestone: "M3",
        kernelRuntime: true,
        providers: true,
        storageEngine: false,
        memoryEngine: false,
        skillRuntime: true,
        toolRuntime: true,
        cognitionLoop: false,
        eventReplay: false
    )
}
