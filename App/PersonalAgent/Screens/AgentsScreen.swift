import SwiftUI

struct AgentsScreen: View {
    @ObservedObject var session: KernelSession

    private var selectedAgent: AgentManifest? {
        session.agentManifests.first(where: { $0.id == session.selectedAgentID })
    }

    var body: some View {
        ScreenScaffold(title: "Agents", systemImage: "person.crop.circle.badge.checkmark") {
            overview
            if let selectedAgent { agentDetail(selectedAgent) }
            agentProfiles
        }
    }

    private var overview: some View {
        GlassPanel {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent profiles").font(.headline)
                    Text("Agent.md is the execution boundary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.agentManifests.count)").font(.title3.bold())
                    Text("profiles").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Each profile declares its allowed Skills and rule. Selecting an Agent changes the real Skill scope used by chat execution.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                scopeBadge("Agent scope", symbol: "scope", tint: .tint)
                scopeBadge("Policy", symbol: "checkmark.shield", tint: .secondary)
                scopeBadge("Verification", symbol: "checkmark.seal", tint: .secondary)
            }
        }
    }

    @ViewBuilder
    private func agentDetail(_ agent: AgentManifest) -> some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name).font(.title3.bold())
                    Text(agent.description).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(agent.version.major).\(agent.version.minor).\(agent.version.patch)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label("Declared Skills", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(agent.skillIDs.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
            }
            if agent.skillIDs.isEmpty {
                Text("No Skills are declared. Execution must remain fail-closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(agent.skillIDs, id: \.rawValue) { skillID in
                    let skill = session.skillManifests.first(where: { $0.id == skillID })
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill?.name ?? skillID.rawValue).font(.subheadline.weight(.semibold))
                            Text(skill?.description ?? "Declared by Agent.md")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
            if !agent.instructions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Agent Rule", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                    Text(agent.instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                Label("Selected for chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Text("Active scope").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
    }

    private var agentProfiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVAILABLE AGENTS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
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
                    profileCard(agent)
                }
            }
        }
    }

    private func profileCard(_ agent: AgentManifest) -> some View {
        let selected = agent.id == session.selectedAgentID
        return Button {
            session.selectAgent(id: agent.id)
        } label: {
            GlassPanel {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(selected ? .tint : .secondary)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(agent.name).font(.headline)
                            Spacer()
                            if selected {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.tint)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.tint.opacity(0.10), in: Capsule())
                            }
                        }
                        Text(agent.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 12) {
                            Label("\(agent.skillIDs.count) Skill\(agent.skillIDs.count == 1 ? "" : "s")", systemImage: "square.stack.3d.up")
                            Label("v\(agent.version.major).\(agent.version.minor).\(agent.version.patch)", systemImage: "number")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .tint : .secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(agent.name), active Agent" : "\(agent.name), select Agent")
    }

    private func scopeBadge(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.08), in: Capsule())
    }
}
