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
        .library(name: "PAFoundation", targets: ["PAFoundation"]),
        .library(name: "PAObservability", targets: ["PAObservability"]),
        .library(name: "PAEvents", targets: ["PAEvents"]),
        .library(name: "PASecurity", targets: ["PASecurity"]),
        .library(name: "PAStorage", targets: ["PAStorage"]),
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
            path: "Frameworks/llama.xcframework"
        ),
        .target(
            name: "cllama",
            dependencies: [
                .target(name: "llama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Sources/cllama",
            exclude: ["README.md"]
        ),
        .target(name: "PAFoundation", dependencies: ["PAKernel"], path: "Sources/Foundation"),
        .target(
            name: "PAObservability",
            dependencies: ["PAFoundation"],
            path: "Sources/Observability"
        ),
        .target(
            name: "PAEvents",
            dependencies: ["PAKernel"],
            path: "Sources/Events"
        ),
        .target(
            name: "PASecurity",
            dependencies: ["PAFoundation"],
            path: "Sources/Security"
        ),
        .target(
            name: "PAStorage",
            dependencies: ["PAFoundation", "PAEvents", "PAObservability"],
            path: "Sources/Storage"
        ),
        .target(
            name: "PAMemory",
            dependencies: ["PAFoundation", "PAStorage", "PAEvents"],
            path: "Sources/Memory"
        ),
        .target(
            name: "PAProviders",
            dependencies: ["PAFoundation", "PAObservability", "PASecurity", "PAEvents"],
            path: "Sources/Providers/Contracts"
        ),
        .target(
            name: "PAProvidersRemote",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Providers/Remote/Shared"
        ),
        .target(
            name: "PAProvidersGrok",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAFoundation"],
            path: "Providers/Remote/Grok"
        ),
        .target(
            name: "PAProvidersOpenAI",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAFoundation"],
            path: "Providers/Remote/OpenAI"
        ),
        .target(
            name: "PAProvidersOpenAICompatible",
            dependencies: ["PAProvidersRemote", "PAProviders", "PAFoundation"],
            path: "Providers/Remote/OpenAICompatible"
        ),
        .target(
            name: "PAProvidersLocal",
            dependencies: [
                "PAProvidersRemote",
                "PAProviders",
                "PAFoundation",
                .target(name: "cllama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Sources/Providers/Local"
        ),
        .target(
            name: "PATools",
            dependencies: ["PAFoundation", "PAObservability", "PARuntime"],
            path: "Sources/Tools/Contracts"
        ),
        .target(
            name: "PAModules",
            dependencies: ["PAKernel", "PAObservability", "PAEvents"],
            path: "Sources/Modules/Contracts"
        ),
        .target(
            name: "PASkills",
            dependencies: ["PAFoundation", "PAModules", "PATools"],
            path: "Sources/Skills/Contracts"
        ),
        .target(
            name: "PAKernel",
            dependencies: [],
            path: "Kernel"
        ),
        .target(
            name: "PARuntime",
            dependencies: [
                "PAFoundation",
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
            ],
            path: "Sources/Composition"
        ),
        .target(
            name: "PAArchitecture",
            dependencies: ["PAFoundation"],
            path: "Sources/Architecture"
        ),
        .testTarget(
            name: "PersonalAgentTests",
            dependencies: [
                "PAFoundation",
                "PAObservability",
                "PAEvents",
                "PASecurity",
                "PAStorage",
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
