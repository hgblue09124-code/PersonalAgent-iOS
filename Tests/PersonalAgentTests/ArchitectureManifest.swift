import PAKernel

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

    /// Target -> allowed imported PA* modules.
    public static let allowedImports: [String: Set<String>] = [
        "PAObservability": ["PAKernel"],
        "PAWorkspace": [],
        "PAEvents": ["PAObservability", "PAKernel"],
        "PASecurity": ["PAKernel"],
        "PAStorage": ["PAEvents", "PAObservability", "PAStorageModels"],
        "PAImportGateway": [],
        "PAStorageModels": ["PAKernel", "PAProviders", "PAProvidersLocal"],
        "PAMemory": ["PAStorage", "PAStorageModels", "PAEvents", "PAKernel"],
        "PAStorageMemory": ["PAMemory", "PAStorage", "PAStorageModels", "PAEvents"],
        "PAProviders": ["PAObservability", "PASecurity", "PAEvents", "PAKernel"],
        "PAProvidersGrok": ["PAKernel", "PAProviders", "PAProvidersRemote"],
        "PAProvidersOpenAI": ["PAKernel", "PAProviders", "PAProvidersRemote"],
        "PAProvidersOpenAICompatible": ["PAKernel", "PAProviders", "PAProvidersRemote"],
        "PAProvidersRemote": ["PAKernel", "PAProviders", "PASecurity"],
        "cllama": [],
        "PAProvidersLocal": ["PAKernel", "PAProviders", "PAProvidersRemote", "cllama"],
        "PATools": ["PARuntime", "PAObservability", "PAKernel"],
        "PAModules": ["PAObservability", "PAEvents", "PAKernel"],
        "PASkills": ["PAModules", "PATools", "PARuntime", "PAKernel"],
        "PATerminal": ["PAWorkspace", "PASkills"],
        "PARuntime": [
            "PAKernel",
            "PAObservability",
            "PAEvents",
            "PAProviders",
            "PAModules",
            "PAMemory",
        ],
        "PAKernel": ["PAEvents", "PAModules"],
        "PAComposition": [
            "PAKernel",
            "PAProvidersRemote",
            "PAProvidersGrok",
            "PAProvidersOpenAI",
            "PAProvidersOpenAICompatible",
            "PAWorkspace",
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
            "PAStorageModels",
            "PAStorageMemory",
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
