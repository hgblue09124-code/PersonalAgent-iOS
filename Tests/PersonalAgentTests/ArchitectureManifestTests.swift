import Testing
import PAArchitecture
import PAFoundation
import PACognition
import PAAgency

@Suite("M0 architecture manifest")
struct ArchitectureManifestTests {
    @Test func milestoneIsM0() {
        #expect(ArchitectureManifest.milestone == "M0")
        #expect(MilestoneGate.m0.kernelRuntime == false)
        #expect(MilestoneGate.m0.providers == false)
    }

    @Test func axisStartsAtUIAndEndsAtFoundation() {
        #expect(ArchitectureManifest.axis.first == "UI")
        #expect(ArchitectureManifest.axis.last == "Foundation")
        #expect(ArchitectureManifest.axis.contains("Kernel"))
    }

    @Test func cognitionPipelineMatchesContractEnum() {
        let fromEnum = CognitionStage.allCases.map(\.rawValue)
        #expect(fromEnum == ArchitectureManifest.cognitionPipeline)
    }

    @Test func agencyLoopMatchesContractEnum() {
        let fromEnum = AgencyStage.allCases.map(\.rawValue)
        #expect(fromEnum == ArchitectureManifest.agencyLoop)
    }

    @Test func companionReposAreForbidden() {
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("living-data-ocean"))
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("agent-core"))
        #expect(ArchitectureManifest.kernelMustNotImport.contains("PAProvidersGrok"))
        #expect(ArchitectureManifest.kernelMustNotImport.contains("SwiftUI"))
    }
}
