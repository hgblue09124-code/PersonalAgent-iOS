import SwiftUI
import PAKernel

struct AgentScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Agent", systemImage: "cpu") {
            MilestoneBanner()
            StatusRow(title: "Lifecycle", value: session.state.lifecycle.rawValue)
            StatusRow(title: "Phase", value: session.state.phase.rawValue)
            StatusRow(title: "Runtime", value: session.milestone.kernelRuntime ? "kernel" : "absent")
            StatusRow(title: "Identity", value: session.state.identity.displayName)
            StatusRow(
                title: "Active goal",
                value: session.state.activeGoalID?.rawValue ?? "none"
            )
            if let lastError = session.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Start") { Task { await session.start() } }
                Button("Pause") { Task { await session.pause() } }
                Button("Resume") { Task { await session.resume() } }
                Button("Stop") { Task { await session.stop() } }
            }
            .buttonStyle(.bordered)
        }
    }
}
