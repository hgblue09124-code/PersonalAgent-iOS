// swift-tools-version: 6.0
import PackageDescription

/// Canonical PersonalAgent-iOS package graph.
///
/// Canonical direction:
///   App -> Composition -> Runtime -> Capabilities/Providers/Memory/Storage -> Kernel
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
        .library(name: "PAPolicy", targets: ["PAPolicy"]),
        .library(name: "PACognition", targets: ["PACognition"]),
        .library(name: "PAAgency", targets: ["PAAgency"]),
        .library(name: "PAKernel", targets: ["PAKernel"]),
        .library(name: "PAComposition", targets: ["PAComposition"]),
        .library(name: "PAArchitecture", targets: ["PAArchitecture"]),
        .library(name: "PAProvidersGrok", targets: ["PAProvidersGrok"]),
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
            path: "Sources/Providers/Local/EngineBridge",
            exclude: ["README.md"]
        ),
        .target(name: "PAFoundation", path: "Sources/Kernel/Foundation"),
        .target(
            name: "PAObservability",
            dependencies: ["PAFoundation"],
            path: "Sources/Runtime/Observability"
        ),
        .target(
            name: "PAEvents",
            dependencies: ["PAFoundation", "PAObservability"],
            path: "Sources/Kernel/Events"
        ),
        .target(
            name: "PASecurity",
            dependencies: ["PAFoundation"],
            path: "Sources/Storage/Security"
        ),
        .target(
            name: "PAStorage",
            dependencies: ["PAFoundation", "PAEvents", "PAObservability"],
            path: "Sources/Storage/Core"
        ),
        .target(
            name: "PAMemory",
            dependencies: ["PAFoundation", "PAStorage", "PAEvents"],
            path: "Sources/Memory/Core"
        ),
        .target(
            name: "PAProviders",
            dependencies: ["PAFoundation", "PAObservability", "PASecurity", "PAEvents"],
            path: "Sources/Providers/Contracts"
        ),
        .target(
            name: "PAProvidersGrok",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/Remote/Grok"
        ),
        .target(
            name: "PAProvidersOpenAI",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/Remote/OpenAI"
        ),
        .target(
            name: "PAProvidersOpenAICompatible",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/Remote/OpenAICompatible"
        ),
        .target(
            name: "PAProvidersLocal",
            dependencies: [
                "PAProviders",
                "PAFoundation",
                .target(name: "cllama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Sources/Providers/Local/Runtime"
        ),
        .target(
            name: "PAPolicy",
            dependencies: ["PAFoundation"],
            path: "Sources/Kernel/Policy"
        ),
        .target(
            name: "PATools",
            dependencies: ["PAFoundation", "PAPolicy", "PAObservability"],
            path: "Sources/Capabilities/Tools"
        ),
        .target(
            name: "PAModules",
            dependencies: ["PAFoundation", "PAPolicy", "PAObservability", "PAEvents"],
            path: "Sources/Capabilities/Modules"
        ),
        .target(
            name: "PASkills",
            dependencies: ["PAFoundation", "PAModules", "PATools", "PAPolicy"],
            path: "Sources/Capabilities/Skills"
        ),
        .target(
            name: "PACognition",
            dependencies: ["PAFoundation", "PAProviders", "PAMemory", "PASkills"],
            path: "Sources/Runtime/Cognition"
        ),
        .target(
            name: "PAAgency",
            dependencies: ["PAFoundation", "PAPolicy", "PATools", "PACognition"],
            path: "Sources/Runtime/Agency"
        ),
        .target(
            name: "PAKernel",
            dependencies: [
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
            path: "Sources/Runtime/Execution"
        ),
        .target(
            name: "PAComposition",
            dependencies: [
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
            ],
            path: "Sources/Composition"
        ),
        .target(
            name: "PAArchitecture",
            dependencies: ["PAFoundation"],
            path: "Sources/Kernel/Architecture"
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
                "PAPolicy",
                "PACognition",
                "PAAgency",
                "PAKernel",
                "PAComposition",
                "PAArchitecture",
            ],
            path: "Tests/PersonalAgentTests"
        ),
    ]
)
