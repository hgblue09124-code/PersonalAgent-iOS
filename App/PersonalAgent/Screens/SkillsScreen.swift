import SwiftUI

struct SkillsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Skills", systemImage: "puzzlepiece") {
            GlassPanel {
                HStack {
                    Label("Registered capabilities", systemImage: "square.stack.3d.up")
                        .font(.headline)
                    Spacer()
                    Text("\(session.moduleIDs.count)")
                        .font(.title3.bold())
                }
                if session.moduleIDs.isEmpty {
                    Text("No skills are currently exposed to the Agent.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.moduleIDs, id: \.self) { id in
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").frame(width: 30, height: 30).background(.thinMaterial, in: Circle())
                            StatusRow(title: "Skill", value: id)
                        }
                    }
                }
            }

            GlassPanel {
                Text("Skills stay contextual to the living Agent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
