import SwiftUI
import PAKernel

struct AgentFeatureHub: View {
    @ObservedObject var session: KernelSession
    @State private var section: HubSection = .overview
    @State private var showChat = false

    var body: some View {
        NavigationStack {
            ZStack {
                AgentDesign.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        runtime
                        picker
                        content
                        boundary
                    }
                    .padding(.horizontal, AgentDesign.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showChat = true } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    }
                }
            }
            .sheet(isPresented: $showChat) { ChatScreen(session: session) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 13) {
                PremiumIconTile(systemImage: "circle.hexagongrid.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Control Center")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("One runtime. Every connected capability.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("This surface observes KernelSession directly. Existing feature screens remain the owners of their capabilities.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runtime: some View {
        HStack(spacing: 8) {
            Metric(title: "Runtime", value: session.state.lifecycle.rawValue, symbol: "bolt.fill", tint: lifecycleTint)
            Metric(title: "Provider", value: session.providerLifecycle, symbol: "server.rack", tint: providerTint)
            Metric(title: "Models", value: "\(session.installedModels.count)", symbol: "cube.box.fill", tint: session.installedModels.isEmpty ? .secondary : .green)
            Metric(title: "Memory", value: "\(session.memoryRecords.count)", symbol: "brain", tint: .purple)
        }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HubSection.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { section = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(section == item ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(section == item ? AgentDesign.accent : Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .overview: overview
        case .chat: chat
        case .runtime: tasks
        case .intelligence: intelligence
        case .system: system
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Heading(title: "Live Agent", detail: "Execution state and the most useful surfaces.")
            GlassPanel {
                HStack(alignment: .top, spacing: 14) {
                    AgentOrb(
                        isActive: session.state.lifecycle.rawValue.lowercased() == "running",
                        isThinking: session.executionProgress != nil
                    )
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.title3.bold())
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack(spacing: 9) {
                    ActionButton(title: "Chat", symbol: "bubble.left.and.bubble.right.fill") { showChat = true }
                    ActionButton(title: "Tasks", symbol: "checklist") { section = .runtime }
                }
            }
            if let progress = session.executionProgress {
                ExecutionCard(progress: progress)
            }
            if let result = session.executionResult {
                ResultCard(result: result)
            }
            if let error = session.lastError {
                ErrorCard(message: error)
            }
            capabilityGrid
            conversation
        }
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 14) {
            Heading(title: "Chat", detail: "History and context share the same execution session.")
            GlassPanel {
                HStack {
                    PremiumIconTile(systemImage: "bubble.left.and.bubble.right.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current conversation").font(.headline)
                        Text(currentTitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                StatusRow(title: "Turns", value: "\(session.chatHistory.count)")
                StatusRow(title: "Conversations", value: "\(session.conversations.count)")
                Button { showChat = true } label {
                    Label("Open full chat", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
            }
            if session.chatHistory.isEmpty {
                EmptyCard(title: "No messages yet", detail: "Start from the Agent composer or open Chat.", symbol: "bubble")
            } else {
                conversation
            }
            NavigationLink { ChatScreen(session: session) } label: {
                LinkCard(title: "Conversation manager", detail: "Switch, rename and delete persistent conversations.", symbol: "rectangle.stack.bubble")
            }
            .buttonStyle(.plain)
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Heading(title: "Runtime", detail: "Lifecycle and execution feedback are live.")
            GlassPanel { LifecycleControls(session: session) }
            if let progress = session.executionProgress { ExecutionCard(progress: progress) }
            if let result = session.executionResult { ResultCard(result: result) }
            if let error = session.lastError { ErrorCard(message: error) }
            NavigationLink { TasksScreen(session: session) } label: {
                LinkCard(title: "Task monitor", detail: "Inspect execution state and latest result.", symbol: "checklist")
            }
            .buttonStyle(.plain)
        }
    }

    private var intelligence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Heading(title: "Intelligence", detail: "All capability surfaces remain connected to the same composition root.")
            NavigationLink { ModelsScreen(session: session) } label {
                CapabilityCard(title: "Models", detail: "Import GGUF, select the active model and manage local lifecycle.", symbol: "cube.box.fill", status: "\(session.installedModels.count)", tint: .green)
            }.buttonStyle(.plain)
            NavigationLink { ProvidersScreen(session: session) } label {
                CapabilityCard(title: "Providers", detail: "Remote credentials and connectivity.", symbol: "server.rack", status: session.providerLifecycle, tint: providerTint)
            }.buttonStyle(.plain)
            NavigationLink { SkillsScreen(session: session) } label {
                CapabilityCard(title: "Skills", detail: "Skill.md capability contracts.", symbol: "puzzlepiece.extension.fill", status: "\(session.skillManifests.count)", tint: .purple)
            }.buttonStyle(.plain)
            NavigationLink { AgentsScreen(session: session) } label {
                CapabilityCard(title: "Agents", detail: "Agent.md scope and Skill selection.", symbol: "person.crop.circle.badge.checkmark", status: "\(session.agentManifests.count)", tint: .orange)
            }.buttonStyle(.plain)
            NavigationLink { MemoryScreen() } label {
                CapabilityCard(title: "Memory", detail: "Persistent context used by chat execution.", symbol: "brain", status: "\(session.memoryRecords.count)", tint: .purple)
            }.buttonStyle(.plain)
            GlassPanel {
                Text("Execution chain").font(.headline)
                ChainRow(number: 1, title: "Request", detail: "Normalize one user goal.")
                ChainRow(number: 2, title: "Context", detail: "Attach recent turns and relevant memory.")
                ChainRow(number: 3, title: "Selection", detail: "Keep Skill selection inside Agent scope.")
                ChainRow(number: 4, title: "Execution", detail: "Run through the existing runtime.")
                ChainRow(number: 5, title: "Verification", detail: "Verify before presenting a result.")
            }
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 14) {
            Heading(title: "System", detail: "Configuration stays contextual and secure.")
            NavigationLink { SettingsScreen(session: session) } label {
                CapabilityCard(title: "Settings", detail: "Provider credentials, model, privacy, language and updates.", symbol: "gearshape.fill", status: "Open", tint: .secondary)
            }.buttonStyle(.plain)
            GlassPanel {
                Text("Open-beta invariants").font(.headline)
                Invariant(title: "One source of truth", detail: "KernelSession owns live UI state.", symbol: "checkmark.circle.fill")
                Invariant(title: "Fail closed", detail: "Unavailable contracts do not become executable actions.", symbol: "lock.fill")
                Invariant(title: "Independent verification", detail: "Execution success is not treated as verified success.", symbol: "checkmark.shield.fill")
                Invariant(title: "Secure credentials", detail: "Provider API keys stay in Keychain-backed storage.", symbol: "key.fill")
            }
        }
    }

    private var capabilityGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Heading(title: "Connected capabilities", detail: "Native surfaces backed by the current runtime.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MiniCard(title: "Chat", value: "\(session.chatHistory.count)", detail: "turns", symbol: "bubble.left.fill", tint: .blue) { showChat = true }
                NavigationLink { ModelsScreen(session: session) } label {
                    MiniCardContent(title: "Models", value: "\(session.installedModels.count)", detail: "installed", symbol: "cube.box.fill", tint: .green)
                }.buttonStyle(.plain)
                NavigationLink { SkillsScreen(session: session) } label {
                    MiniCardContent(title: "Skills", value: "\(session.skillManifests.count)", detail: "loaded", symbol: "puzzlepiece.fill", tint: .purple)
                }.buttonStyle(.plain)
                NavigationLink { MemoryScreen() } label {
                    MiniCardContent(title: "Memory", value: "\(session.memoryRecords.count)", detail: "records", symbol: "brain", tint: .orange)
                }.buttonStyle(.plain)
            }
        }
    }

    private var conversation: some View {
        GlassPanel {
            Heading(title: "Conversation", detail: "Recent turns visible before entering full Chat.")
            ForEach(Array(session.chatHistory.suffix(4))) { turn in
                VStack(alignment: .leading, spacing: 3) {
                    Text(turn.role == .user ? "You" : "Agent")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(turn.content)
                        .font(.subheadline)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if turn.id != session.chatHistory.suffix(4).last?.id { Divider() }
            }
        }
    }

    private var boundary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(AgentDesign.accent)
            Text("UI observes KernelSession; KernelSession composes runtime capabilities. Feature screens do not become alternate runtimes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(AgentDesign.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var currentTitle: String {
        session.conversations.first(where: { $0.id == session.currentConversationID })?.title ?? "New conversation"
    }

    private var headline: String {
        if session.executionProgress != nil { return "Agent is working" }
        if session.executionResult != nil { return "Task complete" }
        if session.lastError != nil { return "Agent needs attention" }
        return "Agent is ready"
    }

    private var detail: String {
        if let p = session.executionProgress { return p.detail }
        if let r = session.executionResult { return r }
        if let e = session.lastError { return e }
        return "Ask anything from the main Agent composer."
    }

    private var lifecycleTint: Color {
        switch session.state.lifecycle.rawValue.lowercased() {
        case "running": return .green
        case "paused": return .orange
        case "stopped": return .secondary
        default: return .blue
        }
    }

    private var providerTint: Color {
        let value = session.providerLifecycle.lowercased()
        if value.contains("ready") || value.contains("connected") || value.contains("saved") { return .green }
        if value.contains("error") || value.contains("failed") { return .red }
        return .secondary
    }
}

private enum HubSection: String, CaseIterable, Identifiable {
    case overview, chat, runtime, intelligence, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .chat: return "Chat"
        case .runtime: return "Runtime"
        case .intelligence: return "Intelligence"
        case .system: return "System"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "circle.grid.2x2.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .runtime: return "bolt.fill"
        case .intelligence: return "sparkles"
        case .system: return "gearshape.fill"
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.caption.bold()).foregroundStyle(tint)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct Heading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct LinkCard: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            PremiumIconTile(systemImage: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CapabilityCard: View {
    let title: String
    let detail: String
    let symbol: String
    let status: String
    let tint: Color
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PremiumIconTile(systemImage: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    StatusBadge(title: status, tint: tint)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MiniCardContent: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PremiumIconTile(systemImage: symbol, tint: tint)
            Text(title).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title3.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 115, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct MiniCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            MiniCardContent(title: title, value: value, detail: detail, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyCard: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AgentDesign.accent)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ExecutionCard: View {
    let progress: ExecutionProgress
    var body: some View {
        GlassPanel {
            HStack(spacing: 11) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.title).font(.headline)
                    Text(progress.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(title: "LIVE", tint: .green)
            }
        }
    }
}

private struct ResultCard: View {
    let result: String
    @State private var expanded = false
    var body: some View {
        GlassPanel {
            HStack {
                Label("Verified result", systemImage: "checkmark.shield.fill").font(.headline)
                Spacer()
                StatusBadge(title: "DONE", tint: .green)
            }
            Text(result).font(.subheadline).lineLimit(expanded ? nil : 6).textSelection(.enabled)
            Button(expanded ? "Show less" : "Show full result") {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }
            .font(.caption.weight(.semibold))
        }
    }
}

private struct ErrorCard: View {
    let message: String
    var body: some View {
        GlassPanel {
            Label("Execution needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(message).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct LifecycleControls: View {
    @ObservedObject var session: KernelSession
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Agent lifecycle", systemImage: "bolt.circle.fill").font(.headline)
                Spacer()
                StatusBadge(title: session.state.lifecycle.rawValue, tint: lifecycleTint)
            }
            HStack(spacing: 8) {
                button("Start", "play.fill") { Task { await session.start() } }
                button("Pause", "pause.fill") { Task { await session.pause() } }
                button("Resume", "play.circle.fill") { Task { await session.resume() } }
                button("Stop", "stop.fill") { Task { await session.stop() } }
            }
        }
    }
    private var lifecycleTint: Color {
        switch session.state.lifecycle.rawValue.lowercased() {
        case "running": return .green
        case "paused": return .orange
        case "stopped": return .secondary
        default: return .blue
        }
    }
    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }
}

private struct Invariant: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ChainRow: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 24, height: 24)
                .background(AgentDesign.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}


private struct HubInvariant1: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 1")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant2: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 2")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant3: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 3")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant4: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 4")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant5: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 5")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant6: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 6")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant7: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 7")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant8: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 8")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant9: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 9")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant10: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 10")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant11: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 11")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant12: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 12")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant13: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 13")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant14: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 14")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant15: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 15")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant16: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 16")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant17: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 17")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant18: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 18")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant19: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 19")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant20: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 20")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant21: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 21")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant22: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 22")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant23: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 23")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant24: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 24")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant25: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 25")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant26: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 26")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant27: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 27")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant28: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 28")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant29: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 29")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant30: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 30")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant31: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 31")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant32: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 32")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant33: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 33")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant34: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 34")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant35: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 35")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant36: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 36")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant37: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 37")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant38: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 38")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant39: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 39")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant40: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 40")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant41: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 41")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant42: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 42")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant43: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 43")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant44: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 44")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant45: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 45")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant46: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 46")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant47: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 47")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant48: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 48")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant49: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 49")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant50: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 50")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant51: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 51")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant52: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 52")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant53: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 53")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant54: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 54")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant55: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 55")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant56: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 56")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant57: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 57")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant58: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 58")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant59: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 59")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant60: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 60")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant61: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 61")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant62: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 62")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant63: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 63")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant64: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 64")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant65: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 65")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant66: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 66")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant67: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 67")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant68: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 68")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant69: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 69")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant70: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 70")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant71: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 71")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct HubInvariant72: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime/UI invariant 72")
                    .font(.caption.weight(.semibold))
                Text("This surface remains derived from the existing composition boundary and carries no independent execution state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}