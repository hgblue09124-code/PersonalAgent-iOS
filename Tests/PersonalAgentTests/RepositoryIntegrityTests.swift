import Foundation
import Testing
import PAArchitecture

@Suite("Repository integrity")
struct RepositoryIntegrityTests {
    @Test func requiredM1KernelSourcesExist() {
        let root = repositoryRoot()
        let kernel = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Core")
            .appendingPathComponent("Agent")
        for name in [
            "AgentRuntime.swift",
            "LifecycleMachine.swift",
            "GoalMachine.swift",
            "GoalManaging.swift",
            "KernelClock.swift",
            "KernelCoordination.swift",
            "KernelError.swift",
            "KernelContracts.swift",
        ] {
            #expect(
                FileManager.default.fileExists(atPath: kernel.appendingPathComponent(name).path),
                "missing kernel source \(name)"
            )
        }
    }

    @Test func requiredM1TestSourcesExist() {
        let tests = repositoryRoot()
            .appendingPathComponent("Tests")
            .appendingPathComponent("PersonalAgentTests")
        for name in [
            "M1LifecycleTests.swift",
            "M1GoalTests.swift",
            "M1EventDeterminismTests.swift",
            "M1ConcurrencyTests.swift",
            "M1CompositionTests.swift",
            "ImportBoundaryTests.swift",
            "ArchitectureManifestTests.swift",
        ] {
            #expect(
                FileManager.default.fileExists(atPath: tests.appendingPathComponent(name).path),
                "missing test \(name)"
            )
        }
    }

    @Test func xcodeSourcesPhaseIncludesKernelSession() throws {
        let pbx = try projectFile()
        #expect(pbx.contains("KernelSession.swift in Sources"))
        #expect(pbx.contains("A2000000000000000000000C /* KernelSession.swift */"))
        #expect(pbx.contains("productName = PAKernel"))
        #expect(pbx.contains("productName = PAComposition"))
    }

    @Test func xcodeAppDoesNotLinkPAMemory() throws {
        let pbx = try projectFile()
        #expect(!pbx.contains("productName = PAMemory"))
        #expect(!pbx.contains("PAMemory in Frameworks"))
    }

    @Test func appSourcesDoNotImportReservedEngines() throws {
        let app = repositoryRoot()
            .appendingPathComponent("App")
            .appendingPathComponent("PersonalAgent")
        let files = try files(under: app, suffix: ".swift")
        #expect(!files.isEmpty)
        var violations: [String] = []
        let forbidden = [
            "PAMemory",
            "PAProvidersGrok",
            "PAProvidersOpenAI",
            "PAProvidersOpenAICompatible",
            "PAProvidersLocal",
            "PAStorage",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in forbidden {
                if importedModules(in: text).contains(name) {
                    violations.append("\(file.lastPathComponent) imports \(name)")
                }
            }
        }
        #expect(violations.isEmpty)
    }

    @Test func compositionDependsOnEventsInPackageGraph() throws {
        let package = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        #expect(package.contains("PAEvents"))
        #expect(package.contains("name: \"PAComposition\""))
        let compositionSlice = package.components(separatedBy: "name: \"PAComposition\"").last ?? ""
        let nextTarget = compositionSlice.components(separatedBy: ".target(").first ?? compositionSlice
        #expect(nextTarget.contains("PAEvents"))
    }

    @Test func ciWorkflowEnforcesSwiftTest() throws {
        let workflow = repositoryRoot()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        #expect(FileManager.default.fileExists(atPath: workflow.path))
        let text = try String(contentsOf: workflow, encoding: .utf8)
        #expect(text.contains("swift test"))
        #expect(text.contains("swift:6."))
    }
}

private func projectFile() throws -> String {
    try String(
        contentsOf: repositoryRoot()
            .appendingPathComponent("PersonalAgent.xcodeproj")
            .appendingPathComponent("project.pbxproj"),
        encoding: .utf8
    )
}
