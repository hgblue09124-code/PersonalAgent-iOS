import SwiftUI
import PAComposition
import PASkills

struct AgentsScreen: View {
    @ObservedObject var session: KernelSession

    private var selectedAgent: AgentManifest? {
        session.agentManifests.first(where: { $0.id == session.selectedAgentID })
    }

    var body: some View {
        ScreenScaffold(title: "Agents", systemImage: "person.crop.circle.badge.checkmark") {
            overview
            if let selectedAgent {
                agentDetail(selectedAgent)
            }
            agentProfiles
            roleLibrary
        }
    }

    private var overview: some View {
        GlassPanel {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Button {
                session.setTeamModeEnabled(!session.teamModeEnabled)
            } label: {
                Label(
                    session.teamModeEnabled ? "Team mode enabled" : "Run matching Skills across Agents",
                    systemImage: session.teamModeEnabled ? "person.3.fill" : "person.3"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isSubmitting)
            if session.isSubmitting {
                Label("Agent đang thực thi — thay đổi Agent và Team mode tạm khóa.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Team mode runs matching declared Skills sequentially across Agent.md profiles. Each result is policy-gated and verified; if no Skill matches, Chat falls back to the main runtime.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                scopeBadge("Agent scope", symbol: "scope", tint: .accentColor)
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
                    .background(Color.accentColor.opacity(0.12), in: Circle())
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
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(agent.name).font(.headline)
                            Spacer()
                            if selected {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.10), in: Capsule())
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
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(session.isSubmitting)
        .accessibilityLabel(selected ? "\(agent.name), active Agent" : "\(agent.name), select Agent")
    }


    private var roleLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent role library").font(.title3.bold())
                Text("8 role blueprints · ideas only, not installed profiles").font(.caption).foregroundStyle(.secondary)
            }
            GlassPanel {
                Label("Agent is fixed; LLM is replaceable", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                Text("Agent.md owns identity, goal, allowed Skills, permissions and verification policy. The LLM is an interchangeable reasoning engine behind a stable contract; changing models must not grant new permissions.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    scopeBadge("Identity", symbol: "person.crop.circle", tint: .accentColor)
                    scopeBadge("Policy", symbol: "checkmark.shield", tint: .secondary)
                    scopeBadge("Skills", symbol: "puzzlepiece", tint: .secondary)
                }
            }
            GlassPanel {
                ForEach(AgentRoleIdea.catalog) { role in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: role.symbol)
                            .font(.title3).foregroundStyle(.tint)
                            .frame(width: 36, height: 36)
                            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(role.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(role.focus).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(role.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func scopeBadge(_ title: String, symbol: String, tint: Color) -> some View {
        Label(LocalizedStringKey(title), systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.08), in: Capsule())
    }
}


private struct AgentRoleIdea: Identifiable {
    let id: String
    let title: String
    let focus: String
    let symbol: String
    let detail: String

    static let catalog: [AgentRoleIdea] = [
        .init(id: "planner", title: "Planner", focus: "Kế hoạch", symbol: "list.number", detail: "Làm rõ mục tiêu, chia việc, quản lý phụ thuộc và định nghĩa tiêu chí hoàn thành."),
        .init(id: "researcher", title: "Researcher", focus: "Tri thức", symbol: "books.vertical", detail: "Tổng hợp nguồn, phân biệt dữ kiện với giả định và ghi rõ điều chưa được xác minh."),
        .init(id: "builder", title: "Builder", focus: "Thực thi", symbol: "hammer", detail: "Thực hiện thay đổi nhỏ qua Skills được cấp quyền, kèm test và bằng chứng."),
        .init(id: "auditor", title: "Auditor", focus: "Đối kháng", symbol: "checkmark.shield", detail: "Tìm phản ví dụ, đường tấn công, lỗi biên và tuyên bố không có bằng chứng."),
        .init(id: "librarian", title: "Librarian", focus: "Memory", symbol: "books.vertical.fill", detail: "Tổ chức tri thức, nguồn gốc, phiên bản, trùng lặp và quy tắc lưu/xóa."),
        .init(id: "operator", title: "Operator", focus: "Workspace", symbol: "terminal", detail: "Điều phối terminal và tệp trong sandbox; kiểm tra trạng thái trước và sau thao tác."),
        .init(id: "analyst", title: "Analyst", focus: "Đánh giá", symbol: "chart.bar.xaxis", detail: "So sánh lựa chọn theo tiêu chí, nêu độ bất định và tránh suy diễn quá dữ liệu."),
        .init(id: "coordinator", title: "Coordinator", focus: "Multi-Agent", symbol: "person.3", detail: "Phân công các Agent, quản lý phụ thuộc, hợp nhất đầu ra và xử lý bất đồng.")
    ]
}
