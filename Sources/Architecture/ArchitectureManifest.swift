import PAFoundation

/// Architecture encoded as data so tests can lock the skeleton without a runtime.
public enum ArchitectureManifest: Sendable {
    public static let contractFoundation = "M0"
    public static let milestone = "M8"
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
        "PAFoundation": ["PAKernel"],
        "PAObservability": ["PAFoundation"],
        "PAEvents": ["PAFoundation", "PAObservability", "PAKernel"],
        "PASecurity": ["PAFoundation"],
        "PAStorage": ["PAFoundation", "PAEvents", "PAObservability"],
        "PAMemory": ["PAFoundation", "PAStorage", "PAEvents", "PAKernel"],
        "PAProviders": ["PAFoundation", "PAObservability", "PASecurity", "PAEvents", "PAKernel"],
        "PAProvidersGrok": ["PAProviders", "PAProvidersRemote", "PAFoundation"],
        "PAProvidersOpenAI": ["PAProviders", "PAProvidersRemote", "PAFoundation"],
        "PAProvidersOpenAICompatible": ["PAProviders", "PAProvidersRemote", "PAFoundation"],
        "PAProvidersRemote": ["PAProviders", "PAFoundation", "PASecurity"],
        "cllama": [],
        "PAProvidersLocal": ["PAProviders", "PAProvidersRemote", "PAFoundation", "cllama"],
        "PATools": ["PAFoundation", "PARuntime", "PAObservability"],
        "PAModules": ["PAFoundation", "PAObservability", "PAEvents", "PAKernel"],
        "PASkills": ["PAFoundation", "PAModules", "PATools", "PARuntime", "PAKernel"],
        "PARuntime": [
            "PAFoundation",
            "PAKernel",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PAModules",
            "PAMemory",
        ],
        "PAKernel": [
            "PAFoundation",
            "PAEvents",
            "PAModules",
        ],
        "PAArchitecture": ["PAFoundation"],
        "PAComposition": [
            "PAFoundation",
            "PAArchitecture",
            "PAKernel",
            "PARuntime",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PAProvidersLocal",
            "PASecurity",
            "PAModules",
            "PASkills",
            "PATools",
            "PAMemory",
        ]
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

    public static let m0 = MilestoneGate(milestone: "M0", kernelRuntime: false, providers: false, storageEngine: false, memoryEngine: false, skillRuntime: false, toolRuntime: false, cognitionLoop: false, eventReplay: false)
    public static let m1 = MilestoneGate(milestone: "M1", kernelRuntime: true, providers: false, storageEngine: false, memoryEngine: false, skillRuntime: false, toolRuntime: false, cognitionLoop: false, eventReplay: false)
    public static let m2 = MilestoneGate(milestone: "M2", kernelRuntime: true, providers: true, storageEngine: false, memoryEngine: false, skillRuntime: false, toolRuntime: false, cognitionLoop: false, eventReplay: false)
    public static let m3 = MilestoneGate(milestone: "M3", kernelRuntime: true, providers: true, storageEngine: false, memoryEngine: false, skillRuntime: true, toolRuntime: true, cognitionLoop: false, eventReplay: false)
    public static let m4 = MilestoneGate(milestone: "M4", kernelRuntime: true, providers: true, storageEngine: true, memoryEngine: true, skillRuntime: true, toolRuntime: true, cognitionLoop: false, eventReplay: false)
    public static let m6 = MilestoneGate(milestone: "M6", kernelRuntime: true, providers: true, storageEngine: true, memoryEngine: true, skillRuntime: true, toolRuntime: true, cognitionLoop: true, eventReplay: false)
    public static let m7 = MilestoneGate(milestone: "M7", kernelRuntime: true, providers: true, storageEngine: true, memoryEngine: true, skillRuntime: true, toolRuntime: true, cognitionLoop: true, eventReplay: false)
    public static let m8 = MilestoneGate(milestone: "M8", kernelRuntime: true, providers: true, storageEngine: true, memoryEngine: true, skillRuntime: true, toolRuntime: true, cognitionLoop: true, eventReplay: false)
}
