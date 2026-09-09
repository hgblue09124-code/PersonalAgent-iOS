import SwiftUI
import PAArchitecture
import PAFoundation

struct AgentScreen: View {
    let gate: MilestoneGate

    var body: some View {
        ScreenScaffold(title: "Agent", systemImage: "cpu") {
            MilestoneBanner()
            StatusRow(title: "Lifecycle", value: "not started")
            StatusRow(title: "Phase", value: AgentPhase.idle.rawValue)
            StatusRow(title: "Runtime", value: gate.kernelRuntime ? "live" : "absent (M1)")
            StatusRow(title: "Identity", value: "uninitialized")
        }
    }
}
