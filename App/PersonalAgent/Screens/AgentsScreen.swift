import SwiftUI

struct AgentsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Agents", systemImage: "person.crop.circle.badge.checkmark") {
            GlassPanel {
                HStack {
                    Label("Agent profiles", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Spacer()
                    Text("\(session.agentManifests.count)")
                        .font(.title3.bold())
                }
                Text("Each Agent.md profile declares its allowed Skills and rule. Selecting a profile changes the real execution scope for chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if session.agentManifests.isEmpty {
                GlassPanel {
                    ContentUnavailableView(
                        "No Agent profiles",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("The Agent store has no valid Agent.md profile.")
                    )
                }
            } else {
                ForEach(session.agentManifests, id: \.id) { agent in
                    Button {
                        session.selectAgent(id: agent.id)
                    } label: {
                        GlassPanel {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: agent.id == session.selectedAgentID ? "checkmark.circle.fill" : "person.crop.circle")
                                    .font(.title2)
                                    .foregroundStyle(agent.id == session.selectedAgentID ? .tint : .secondary)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(agent.name).font(.headline)
                                        Spacer()
                                        Text("\(agent.version.major).\(agent.version.minor).\(agent.version.patch)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(agent.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(agent.skillIDs.count) scoped Skill\(agent.skillIDs.count == 1 ? "" : "s")")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
