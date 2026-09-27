import SwiftUI

struct TasksScreen: View {
    var body: some View {
        ScreenScaffold(title: "Tasks", systemImage: "checklist") {
            GlassPanel {
                Label("Agent activity", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Text("Task progress is surfaced by the living Agent on the home surface.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
