// swift-tools-version: 6.0
import PackageDescription

/// M0–M3 package graph.
///
/// Dependency direction is downward only:
///   App -> Composition -> Kernel -> Cognition/Agency/Policy
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
        .target(name: "PAFoundation", path: "Sources/Foundation"),
        .target(
            name: "PAObservability",
            dependencies: ["PAFoundation"],
            path: "Sources/Observability"
        ),
        .target(
            name: "PAEvents",
            dependencies: ["PAFoundation", "PAObservability"],
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
            name: "PAProvidersGrok",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/Grok"
        ),
        .target(
            name: "PAProvidersOpenAI",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/OpenAI"
        ),
        .target(
            name: "PAProvidersOpenAICompatible",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/OpenAICompatible"
        ),
        .target(
            name: "PAProvidersLocal",
            dependencies: ["PAProviders", "PAFoundation"],
            path: "Sources/Providers/Local"
        ),
        .target(
            name: "PAPolicy",
            dependencies: ["PAFoundation"],
            path: "Sources/Core/Policy"
        ),
        .target(
            name: "PATools",
            dependencies: ["PAFoundation", "PAPolicy", "PAObservability"],
            path: "Sources/Tools/Contracts"
        ),
        .target(
            name: "PAModules",
            dependencies: ["PAFoundation", "PAPolicy", "PAObservability", "PAEvents"],
            path: "Sources/Modules/Contracts"
        ),
        .target(
            name: "PASkills",
            dependencies: ["PAFoundation", "PAModules", "PATools", "PAPolicy"],
            path: "Sources/Skills/Contracts"
        ),
        .target(
            name: "PACognition",
            dependencies: ["PAFoundation", "PAProviders", "PAMemory", "PASkills"],
            path: "Sources/Core/Cognition"
        ),
        .target(
            name: "PAAgency",
            dependencies: ["PAFoundation", "PAPolicy", "PATools", "PACognition"],
            path: "Sources/Core/Agency"
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
            ],
            path: "Sources/Core/Agent"
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
                "PASecurity",
                "PAModules",
                "PASkills",
                "PATools",
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
