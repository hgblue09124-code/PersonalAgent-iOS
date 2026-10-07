import SwiftUI
import PAKernel

/// Open-beta control surface for the existing Agent runtime.
/// This view owns presentation only; KernelSession remains the single UI state source.
struct AgentFeatureHub: View {
    @ObservedObject var session: KernelSession
    @State private var section: HubSection = .overview
    @State private var showChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    healthStrip
                    sectionPicker
                    sectionContent
                    boundaryNote
                }
                .padding(.horizontal, AgentDesign.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(AgentDesign.background)
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showChat = true } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    }
                    .accessibilityLabel("Open chat")
                }
            }
            .sheet(isPresented: $showChat) {
                ChatScreen(session: session)
            }
        }
    }

    private var header: some View {
        HubPanel {
            HStack(spacing: 14) {
                AgentOrb(
                    isActive: session.state.lifecycle.rawValue.lowercased() == "running",
                    isThinking: session.executionProgress != nil
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Control Center")
                        .font(.title2.weight(.bold))
                    Text("One runtime · connected capabilities")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var healthStrip: some View {
        HStack(spacing: 8) {
            HealthMetric(
                title: "Runtime",
                value: session.state.lifecycle.rawValue,
                symbol: "bolt.fill",
                tint: lifecycleTint
            )
            HealthMetric(
                title: "Provider",
                value: session.providerLifecycle,
                symbol: "server.rack",
                tint: providerTint
            )
            HealthMetric(
                title: "Models",
                value: "\(session.installedModels.count)",
                symbol: "cube.box.fill",
                tint: session.installedModels.isEmpty ? .secondary : .green
            )
            HealthMetric(
                title: "Memory",
                value: "\(session.memoryRecords.count)",
                symbol: "brain",
                tint: .purple
            )
        }
    }

    private var sectionPicker: some View {
        Picker("Agent section", selection: $section) {
            ForEach(HubSection.allCases) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Agent capability section")
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .overview:
            overview
        case .chat:
            chat
        case .runtime:
            runtime
        case .intelligence:
            intelligence
        case .system:
            system
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubHeading(title: headline, detail: headlineDetail)

            if let progress = session.executionProgress {
                ExecutionCard(progress: progress)
            }

            if let result = session.executionResult {
                ResultCard(result: result)
            }

            if let error = session.lastError {
                ErrorCard(message: error)
            }

            HubPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start here")
                        .font(.headline)

                    HStack(spacing: 10) {
                        HubAction(title: "Chat", symbol: "bubble.left.and.bubble.right.fill") {
                            showChat = true
                        }
                        HubAction(title: "Runtime", symbol: "bolt.fill") {
                            section = .runtime
                        }
                    }
                }
            }

            capabilityGrid
            recentConversation
        }
    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubHeading(
                title: "Chat",
                detail: "Persistent conversations use the same execution session."
            )

            HubPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        HubIcon(symbol: "bubble.left.and.bubble.right.fill", tint: .blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(session.chatHistory.count) turns · \(session.conversations.count) conversations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    Button { showChat = true } label: {
                        Label("Open full chat", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if session.chatHistory.isEmpty {
                EmptyState(
                    title: "No messages yet",
                    detail: "Open Chat and send the first request.",
                    symbol: "bubble"
                )
            } else {
                recentConversation
            }

            NavigationLink {
                ChatScreen(session: session)
            } label: {
                HubLink(
                    title: "Conversation manager",
                    detail: "Switch, rename and delete saved conversations.",
                    symbol: "rectangle.stack.bubble"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var runtime: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubHeading(
                title: "Runtime",
                detail: "Lifecycle and execution feedback are live."
            )

            HubPanel {
                LifecycleControls(session: session)
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

            NavigationLink {
                TasksScreen(session: session)
            } label: {
                HubLink(
                    title: "Task monitor",
                    detail: "Inspect execution state and latest result.",
                    symbol: "checklist"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var intelligence: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubHeading(
                title: "Intelligence",
                detail: "Models, providers, skills, agents and memory stay on their existing owners."
            )

            capability(
                title: "Models",
                detail: "Import GGUF and manage the active local model.",
                symbol: "cube.box.fill",
                value: "\(session.installedModels.count)",
                tint: .green
            ) {
                ModelsScreen(session: session)
            }

            capability(
                title: "Providers",
                detail: "Manage remote connectivity and credentials.",
                symbol: "server.rack",
                value: session.providerLifecycle,
                tint: providerTint
            ) {
                ProvidersScreen(session: session)
            }

            capability(
                title: "Skills",
                detail: "Inspect Skill.md contracts available to the runtime.",
                symbol: "puzzlepiece.extension.fill",
                value: "\(session.skillManifests.count)",
                tint: .purple
            ) {
                SkillsScreen(session: session)
            }

            capability(
                title: "Agents",
                detail: "Inspect Agent.md scope and skill selection.",
                symbol: "person.crop.circle.badge.checkmark",
                value: "\(session.agentManifests.count)",
                tint: .orange
            ) {
                AgentsScreen(session: session)
            }

            capability(
                title: "Memory",
                detail: "Review persistent context used by the product.",
                symbol: "brain",
                value: "\(session.memoryRecords.count)",
                tint: .purple
            ) {
                MemoryScreen()
            }

            executionChain
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 14) {
            HubHeading(
                title: "System",
                detail: "Configuration and product safeguards."
            )

            NavigationLink {
                SettingsScreen(session: session)
            } label: {
                HubLink(
                    title: "Settings",
                    detail: "Provider, model, privacy, language and updates.",
                    symbol: "gearshape.fill"
                )
            }
            .buttonStyle(.plain)

            HubPanel {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Open-beta safeguards")
                        .font(.headline)

                    Safeguard(
                        title: "Single state source",
                        detail: "UI derives live state from KernelSession.",
                        symbol: "checkmark.circle.fill"
                    )
                    Safeguard(
                        title: "Fail closed",
                        detail: "Unavailable capabilities do not become actions.",
                        symbol: "lock.fill"
                    )
                    Safeguard(
                        title: "Verified result",
                        detail: "Execution completion is not presented as verification by itself.",
                        symbol: "checkmark.shield.fill"
                    )
                    Safeguard(
                        title: "Secure credentials",
                        detail: "Provider secrets remain behind the existing secure storage boundary.",
                        symbol: "key.fill"
                    )
                }
            }
        }
    }

    private var capabilityGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connected capabilities")
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                HubMetricCard(
                    title: "Chat",
                    value: "\(session.chatHistory.count)",
                    detail: "turns",
                    symbol: "bubble.left.fill",
                    tint: .blue
                ) {
                    showChat = true
                }

                NavigationLink {
                    ModelsScreen(session: session)
                } label: {
                    HubMetricCardContent(
                        title: "Models",
                        value: "\(session.installedModels.count)",
                        detail: "installed",
                        symbol: "cube.box.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SkillsScreen(session: session)
                } label: {
                    HubMetricCardContent(
                        title: "Skills",
                        value: "\(session.skillManifests.count)",
                        detail: "loaded",
                        symbol: "puzzlepiece.fill",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MemoryScreen()
                } label: {
                    HubMetricCardContent(
                        title: "Memory",
                        value: "\(session.memoryRecords.count)",
                        detail: "records",
                        symbol: "brain",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentConversation: some View {
        HubPanel {
            VStack(alignment: .leading, spacing: 10) {
                HubHeading(
                    title: "Recent conversation",
                    detail: "Latest turns from the current session."
                )

                let recent = Array(session.chatHistory.suffix(4))
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, turn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.role == .user ? "You" : "Agent")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(turn.content)
                            .font(.subheadline)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if index < recent.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var executionChain: some View {
        HubPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Execution boundary")
                    .font(.headline)

                ChainStep(number: 1, title: "Request", detail: "Normalize the user's goal.")
                ChainStep(number: 2, title: "Context", detail: "Attach conversation and relevant memory.")
                ChainStep(number: 3, title: "Selection", detail: "Keep skills inside Agent scope.")
                ChainStep(number: 4, title: "Execution", detail: "Run through the existing runtime.")
                ChainStep(number: 5, title: "Verification", detail: "Verify before presenting a result.")
            }
        }
    }

    private func capability<Destination: View>(
        title: String,
        detail: String,
        symbol: String,
        value: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            CapabilityRow(
                title: title,
                detail: detail,
                symbol: symbol,
                value: value,
                tint: tint
            )
        }
        .buttonStyle(.plain)
    }

    private var boundaryNote: some View {
        Label {
            Text("Presentation observes KernelSession. Feature screens remain capability owners; this hub does not create a second runtime.")
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AgentDesign.accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var currentTitle: String {
        session.conversations.first {
            $0.id == session.currentConversationID
        }?.title ?? "New conversation"
    }

    private var headline: String {
        if session.executionProgress != nil { return "Agent is working" }
        if session.executionResult != nil { return "Task complete" }
        if session.lastError != nil { return "Agent needs attention" }
        return "Agent is ready"
    }

    private var headlineDetail: String {
        if let progress = session.executionProgress { return progress.detail }
        if let result = session.executionResult { return result }
        if let error = session.lastError { return error }
        return "Use the main Agent composer to start a request."
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
        if value.contains("ready") || value.contains("connected") || value.contains("saved") {
            return .green
        }
        if value.contains("error") || value.contains("failed") {
            return .red
        }
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

private struct HubPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct HubHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HealthMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct HubIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HubAction: View {
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

private struct HubLink: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            HubIcon(symbol: symbol, tint: AgentDesign.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct CapabilityRow: View {
    let title: String
    let detail: String
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HubIcon(symbol: symbol, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HubMetricCardContent: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubIcon(symbol: symbol, tint: tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct HubMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HubMetricCardContent(
                title: title,
                value: value,
                detail: detail,
                symbol: symbol,
                tint: tint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value) \(detail)")
    }
}

private struct EmptyState: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(AgentDesign.accent)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ExecutionCard: View {
    let progress: ExecutionProgress

    var body: some View {
        HubPanel {
            HStack(spacing: 11) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.title)
                        .font(.headline)
                    Text(progress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                StatusBadge(title: "LIVE", tint: .green)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent working: \(progress.title). \(progress.detail)")
    }
}

private struct ResultCard: View {
    let result: String
    @State private var expanded = false

    var body: some View {
        HubPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Result", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Spacer()
                    StatusBadge(title: "DONE", tint: .green)
                }

                Text(result)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 6)
                    .textSelection(.enabled)

                Button(expanded ? "Show less" : "Show full result") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HubPanel {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Needs attention")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent error: \(message)")
    }
}

private struct ChainStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(AgentDesign.accent.opacity(0.12), in: Circle())
                .foregroundStyle(AgentDesign.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Safeguard: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
