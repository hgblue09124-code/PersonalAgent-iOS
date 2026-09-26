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
        "cllama": [],
        "PAProvidersLocal": ["PAProviders", "PAFoundation", "cllama"],
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
            "PAMemory",
        ],
        "PAArchitecture": ["PAFoundation"],
        "PAComposition": [
            "PAFoundation",
            "PAArchitecture",
            "PAKernel",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PAProvidersLocal",
            "PASecurity",
            "PAModules",
            "PASkills",
            "PATools",
            "PAMemory",
            "PAPolicy",
            "PACognition",
            "PAAgency",
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
