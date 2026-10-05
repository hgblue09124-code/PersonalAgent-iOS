import SwiftUI

struct SkillsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Skills", systemImage: "puzzlepiece") {
            GlassPanel {
                HStack {
                    Label("Available Skills", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text("\(session.skillManifests.count)")
                        .font(.title3.bold())
                }

                if session.skillManifests.isEmpty {
                    ContentUnavailableView(
                        "No Skills",
                        systemImage: "puzzlepiece",
                        description: Text("No Skill.md capability is currently available to the Agent.")
                    )
                } else {
                    ForEach(session.skillManifests, id: \.id) { skill in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 38, height: 38)
                                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(skill.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(skill.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(skill.id.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(skill.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            GlassPanel {
                Label("Agent scope", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text("Agent.md controls which declared Skills may be selected. Execution remains policy-gated and independently verified.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
