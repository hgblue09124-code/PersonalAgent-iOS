// swift-tools-version: 6.0
import PackageDescription

/// M8 package graph.
///
/// Dependency direction is downward only:
///   App -> Composition -> Runtime -> Kernel -> Cognition/Agency/Policy
///        -> Skills/Tools/Modules/Providers/Memory
///        -> Storage/Events/Observability/Security
///        -> Foundation
///
/// Concrete provider modules exist as reserved boundaries for M2.
/// They must not be imported by Kernel.
let package = Package(
    name: "PersonalAgent",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PAObservability", targets: ["PAObservability"]),
        .library(name: "PAEvents", targets: ["PAEvents"]),
        .library(name: "PASecurity", targets: ["PASecurity"]),
        .library(name: "PAStorage", targets: ["PAStorage"]),
        .library(name: "PAStorageModels", targets: ["PAStorageModels"]),
        .library(name: "PAMemory", targets: ["PAMemory"]),
        .library(name: "PAProviders", targets: ["PAProviders"]),
        .library(name: "PATools", targets: ["PATools"]),
        .library(name: "PAModules", targets: ["PAModules"]),
        .library(name: "PASkills", targets: ["PASkills"]),
        .library(name: "PAKernel", targets: ["PAKernel"]),
        .library(name: "PARuntime", targets: ["PARuntime"]),
        .library(name: "PAComposition", targets: ["PAComposition"]),
        .library(name: "PAArchitecture", targets: ["PAArchitecture"]),
        .library(name: "PAProvidersGrok", targets: ["PAProvidersGrok"]),
        .library(name: "PAProvidersRemote", targets: ["PAProvidersRemote"]),
        .library(name: "PAProvidersOpenAI", targets: ["PAProvidersOpenAI"]),
        .library(name: "PAProvidersOpenAICompatible", targets: ["PAProvidersOpenAICompatible"]),
        .library(name: "PAProvidersLocal", targets: ["PAProvidersLocal"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "Providers/Local/LlamaCPP/llama.xcframework"
        ),
        .target(
            name: "cllama",
            dependencies: [
                .target(name: "llama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Providers/Local/LlamaCPP/cllama",
            exclude: ["README.md"]
        ),
        .target(
            name: "PAObservability",
            dependencies: ["PAKernel"],
            path: "Sources/Observability"
        ),
        .target(
            name: "PAEvents",
            dependencies: ["PAKernel"],
            path: "Kernel/Events"
        ),
        .target(
            name: "PASecurity",
            dependencies: ["PAKernel"],
            path: "Sources/Security"
        ),
        .target(
            name: "PAStorage",
            dependencies: ["PAKernel", "PAEvents", "PAObservability"],
            path: "Sources/Storage"
        ),
        .target(
            name: "PAStorageModels",
            dependencies: ["PAKernel", "PAProviders", "PAProvidersLocal"],
            path: "Storage/Models"
        ),
        .target(
            name: "PAMemory",
            dependencies: ["PAKernel", "PAStorage", "PAEvents"],
            path: "Sources/Memory"
        ),
        .target(
            name: "PAProviders",
            dependencies: ["PAKernel"],
            path: "Kernel/Ports/Providers"
        ),
        .target(
            name: "PAProvidersRemote",
            dependencies: ["PAProviders", "PAKernel", "PASecurity"],
            path: "Providers/Remote/Shared"
        ),
        .target(
            name: "PAProvidersGrok",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAKernel"],
            path: "Providers/Remote/Grok"
        ),
        .target(
            name: "PAProvidersOpenAI",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAKernel"],
            path: "Providers/Remote/OpenAI"
        ),
        .target(
            name: "PAProvidersOpenAICompatible",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAKernel"],
            path: "Providers/Remote/OpenAICompatible"
        ),
        .target(
            name: "PAProvidersLocal",
            dependencies: [
                "PAProvidersRemote",
                "PAProviders",
                "PAKernel",
                .target(name: "cllama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Providers/Local",
            exclude: ["LlamaCPP/cllama"]
        ),
        .target(
            name: "PATools",
            dependencies: ["PAKernel", "PAObservability", "PARuntime"],
            path: "Sources/Tools/Contracts"
        ),
        .target(
            name: "PAModules",
            dependencies: ["PAKernel", "PAObservability", "PAEvents"],
            path: "Sources/Modules/Contracts"
        ),
        .target(
            name: "PASkills",
            dependencies: ["PAKernel", "PAModules", "PATools"],
            path: "Sources/Skills/Contracts"
        ),
        .target(
            name: "PAKernel",
            dependencies: [],
            path: "Kernel",
            exclude: ["Events", "Ports/Providers"]
        ),
        .target(
            name: "PARuntime",
            dependencies: [
                "PAKernel",
                "PAObservability",
                "PAEvents",
                "PAProviders",
                "PAModules",
                "PAMemory",
                "PAKernel",
            ],
            path: "Runtime"
        ),
        .target(
            name: "PAComposition",
            dependencies: [
                "PAKernel",
                "PAArchitecture",
                "PAKernel",
                "PARuntime",
                "PAObservability",
                "PAEvents",
                "PAProviders",
                "PAProvidersLocal",
                "PAStorageModels",

                "PASecurity",
                "PAModules",
                "PASkills",
                "PATools",
                "PAMemory",
            ],
            path: "Sources/Composition"
        ),
        .target(
            name: "PAArchitecture",
            dependencies: ["PAKernel"],
            path: "Sources/Architecture"
        ),
        .testTarget(
            name: "PersonalAgentTests",
            dependencies: [
                "PAKernel",
                "PAObservability",
                "PAEvents",
                "PASecurity",
                "PAStorage",
                "PAStorageModels",
                "PAMemory",
                "PAProviders",
                "PAProvidersGrok",
                "PAProvidersOpenAI",
                "PAProvidersOpenAICompatible",
                "PAProvidersLocal",
                "PATools",
                "PAModules",
                "PASkills",

                "PAKernel",
                "PARuntime",
                "PAComposition",
                "PAArchitecture",
            ],
            path: "Tests/PersonalAgentTests"
        ),
    ]
)
