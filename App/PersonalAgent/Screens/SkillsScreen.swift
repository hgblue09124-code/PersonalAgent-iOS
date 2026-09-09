import SwiftUI
import PAArchitecture

struct SkillsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Skills", systemImage: "puzzlepiece") {
            MilestoneBanner()
            StatusRow(title: "modules", value: "\(session.moduleIDs.count)")
            ForEach(session.moduleIDs, id: \.self) { id in
                StatusRow(title: id, value: "registered")
            }
            Text("Module runtime is live. This screen does not execute skills or privileged tools.")
                .foregroundStyle(.secondary)
        }
    }
}
