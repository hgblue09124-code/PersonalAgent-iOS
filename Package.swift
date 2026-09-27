// swift-tools-version: 6.0
import PackageDescription

/// M0–M6 package graph.
/// Dependency direction is downward only:
/// App -> Composition -> Kernel -> Cognition/Agency/Policy
/// -> Skills/Tools/Modules/Providers/Memory
/// -> Storage/Events/Observability/Security
/// -> Foundation

let package = Package(
    name: "PersonalAgent",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PAKernel", targets: ["PAKernel"]),
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
        .library(name: "PAComposition", targets: ["PAComposition"]),
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
            path: "Sources/cllama",
            exclude: ["README.md"]
        ),
        .target(
            name: "PAKernel",
            dependencies: [],
            path: "Kernel",
            exclude: ["Events"]
        ),
        .target(
            name: "PAObservability",
            dependencies: ["PAKernel"],
            path: "Sources/Observability"
        ),
        .target(
            name: "PAEvents",
            dependencies: ["PAKernel", "PAObservability"],
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
            name: "PAMemory",
            dependencies: ["PAKernel", "PAStorage", "PAEvents"],
            path: "Sources/Memory"
        ),
        .target(
            name: "PAProviders",
            dependencies: ["PAKernel", "PAObservability", "PASecurity", "PAEvents"],
            path: "Sources/Providers/Contracts"
        ),
        .target(
            name: "PAProvidersGrok",
            dependencies: ["PAProviders", "PAKernel"],
            path: "Sources/Providers/Grok"
        ),
        .target(
            name: "PAProvidersOpenAI",
            dependencies: ["PAProviders", "PAKernel"],
            path: "Sources/Providers/OpenAI"
        ),
        .target(
            name: "PAProvidersOpenAICompatible",
            dependencies: ["PAProviders", "PAKernel"],
            path: "Sources/Providers/OpenAICompatible"
        ),
        .target(
            name: "PAProvidersLocal",
            dependencies: [
                "PAProviders",
                "PAKernel",
                .target(name: "cllama", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Sources/Providers/Local"
        ),
        .target(
            name: "PACognition",
            dependencies: ["PAKernel", "PAProviders", "PAMemory", "PASkills"],
            path: "Sources/Core/Cognition"
        ),
        .target(
            name: "PAAgency",
            dependencies: ["PAKernel", "PAPolicy", "PATools", "PACognition"],
            path: "Sources/Core/Agency"
        ),
        .target(
            name: "PAComposition",
            dependencies: [
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
            path: "Composition"
        ),
        .testTarget(
            name: "PersonalAgentTests",
            dependencies: [
                "PAKernel",
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
                "PAComposition",
            ],
            path: "Tests/PersonalAgentTests"
        ),
    ]
)