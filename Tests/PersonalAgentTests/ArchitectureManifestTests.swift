import Testing
import PAArchitecture
import PAFoundation
import PACognition
import PAAgency

@Suite("M0 architecture manifest")
struct ArchitectureManifestTests {
    @Test func contractFoundationRemainsM0() {
        #expect(ArchitectureManifest.contractFoundation == "M0")
        #expect(MilestoneGate.m0.kernelRuntime == false)
        #expect(MilestoneGate.m0.providers == false)
    }

    @Test func currentMilestoneIsM2ProviderRuntime() {
        #expect(ArchitectureManifest.milestone == "M2")
        #expect(ArchitectureManifest.contractFoundation == "M0")
        #expect(MilestoneGate.m1.kernelRuntime == true)
        #expect(MilestoneGate.m1.providers == false)
        #expect(MilestoneGate.m2.kernelRuntime == true)
        #expect(MilestoneGate.m2.providers == true)
        #expect(MilestoneGate.m2.cognitionLoop == false)
        #expect(MilestoneGate.m2.storageEngine == false)
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
