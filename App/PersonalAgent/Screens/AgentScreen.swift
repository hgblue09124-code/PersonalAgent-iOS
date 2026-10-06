import SwiftUI
import PAKernel
import PARuntime

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @Binding var showWorkspace: Bool
    @State private var task = ""
    @State private var showAgentPanel = false
    @State private var appeared = false
    @State private var showActivity = false
    @State private var showCommandCenter = false
    @FocusState private var taskFocused: Bool

    var body: some View {
        ZStack {
            background
            content
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAgentPanel) { AgentContextSheet(session: session).presentationDetents([.fraction(0.42), .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showActivity) { ActivitySheet(session: session).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showCommandCenter) {
            CommandCenterSheet(
                task: $task,
                focused: $taskFocused,
                onSubmit: runTask
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appeared = true } }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.20, blue: 0.78),
                    Color(red: 0.055, green: 0.08, blue: 0.30),
                    Color(red: 0.025, green: 0.035, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 220)
                .blur(radius: 60)
                .offset(x: -110, y: -280)
            Circle()
                .fill(AgentDesign.accent.opacity(0.22))
                .frame(width: 280)
                .blur(radius: 80)
                .offset(x: 130, y: 260)
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        // Keep the Agent surface on its compact design rhythm. In a true
        // fullscreen window, unconstrained Spacers expand with the viewport
        // and destroy the proportions that were correct on the original
        // compact canvas. Fixed rhythm + centered composition preserves that
        // visual geometry without changing the native fullscreen canvas.
        VStack(spacing: 0) {
            topBar
            Color.clear.frame(height: 22)
            quickActions
            Color.clear.frame(height: 18)
            hero
            Color.clear.frame(height: 28)
            composer
            status
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            Text("PERSONAL AGENT")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.82))

            Spacer()

            HStack(spacing: 8) {
                Button { showWorkspace = true } label: { topButton("circle.grid.2x2.fill") }
                Button { showActivity = true } label: { topButton("waveform.path.ecg") }
                lifecycleMenu
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickAction("New task", "plus") { showCommandCenter = true }
            quickAction("Chat", "bubble.left.and.bubble.right") { showWorkspace = true }
            quickAction("Activity", "waveform.path.ecg") { showActivity = true }
            quickAction("Agent", "sparkles") { showAgentPanel = true }
            Spacer()
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.08), value: appeared)
    }

    private func quickAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                 .background(.white.opacity(0.085), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func topButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
             .background(.white.opacity(0.085), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Button { showAgentPanel = true } label: {
                AgentOrb(
                    isActive: session.state.lifecycle.rawValue.lowercased() == "running",
                    isThinking: session.executionProgress != nil
                )
            }
            .buttonStyle(.plain)

            Text(LocalizedStringKey(greeting))
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(-1.3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 7) {
                Circle()
                    .fill(session.executionProgress != nil ? .white : .white.opacity(0.72))
                    .frame(width: 6, height: 6)
                Text(LocalizedStringKey(phaseSubtitle))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Ask Agent…", text: $task, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(1...4)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit { runTask() }

            Button(action: runTask) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
            }
            .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
            .accessibilityLabel("Run Agent")
        }
        .padding(.leading, 17)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
         .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
    }

    @ViewBuilder
    private var status: some View {
        if let result = session.executionResult {
            statusCard(title: "Done", detail: result, symbol: "checkmark.circle.fill")
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if let progress = session.executionProgress {
            statusCard(title: progress.title, detail: progress.detail, symbol: "sparkles")
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let error = session.lastError {
            statusCard(title: "Something went wrong", detail: error, symbol: "exclamationmark.triangle.fill")
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func statusCard(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline.bold())
                ScrollView(.vertical, showsIndicators: true) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 116)
                .scrollDismissesKeyboard(.interactively)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
         .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .padding(.top, 14)
    }

    private var lifecycleMenu: some View {
        Menu {
            Button("Start") { Task { await session.start() } }
            Button("Pause") { Task { await session.pause() } }
            Button("Resume") { Task { await session.resume() } }
            Button("Stop", role: .destructive) { Task { await session.stop() } }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.11), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
        }
        .accessibilityLabel("Agent runtime controls")
    }

    private var phaseSubtitle: String {
        if session.executionProgress != nil { return "I’m thinking through it now." }
        if session.executionResult != nil { return "That task is complete. What’s next?" }
        if session.lastError != nil { return "Let’s adjust the request and try again." }
        return "Tell me what you want to get done."
    }

    private var greeting: String {
        switch session.state.lifecycle.rawValue.lowercased() {
        case "running": return "I’m working."
        case "paused": return "I’m paused."
        case "stopped": return "Ready when you are."
        default: return "What can I do for you?"
        }
    }

    private func runTask() {
        let statement = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty else { return }
        taskFocused = false
        task = ""
        Task { await session.submitGoal(statement) }
    }
}


private struct CommandCenterSheet: View {
    @Binding var task: String
    @FocusState.Binding var focused: Bool
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let suggestions = [
        ("Plan my next step", "sparkles"),
        ("Summarize what changed", "text.alignleft"),
        ("Check my local setup", "checkmark.shield"),
        ("Help me get started", "arrow.right.circle")
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("What should we do?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Start with a thought. The Agent will turn it into an action.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField("Tell Agent…", text: $task, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($focused)
                        .lineLimit(1...4)
                    Button {
                        focused = false
                        onSubmit()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.bold())
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(.primary.opacity(0.92), in: Circle())
                    }
                    .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 1))

                Text("TRY ONE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(suggestions, id: \.0) { suggestion in
                        Button {
                            task = suggestion.0
                            focused = false
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.1)
                                Text(LocalizedStringKey(suggestion.0))
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
        }
    }
}

private struct AgentContextSheet: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AgentOrb(isActive: session.state.lifecycle.rawValue.lowercased() == "running", isThinking: session.executionProgress != nil)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent").font(.title2.bold())
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 10) {
                    row("Lifecycle", session.state.lifecycle.rawValue.capitalized, "bolt.fill")
                    row("Mode", session.executionProgress == nil ? "Idle" : "Working", "waveform")
                    row("Surface", "Living Agent", "sparkles")
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Spacer()
            }
            .padding(20)
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var subtitle: String {
        session.executionProgress != nil ? "Thinking through the current task." : "Quiet, ready and waiting."
    }

    private func row(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}

private struct ActivitySheet: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        AgentOrb(isActive: session.state.lifecycle.rawValue.lowercased() == "running", isThinking: session.executionProgress != nil)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Agent activity").font(.title2.bold())
                            Text(session.state.lifecycle.rawValue.capitalized).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let progress = session.executionProgress {
                        card("WORKING NOW", progress.title, progress.detail, "sparkles")
                    } else if let result = session.executionResult {
                        card("COMPLETED", "Latest result", result, "checkmark.circle.fill")
                    } else if let error = session.lastError {
                        card("NEEDS ATTENTION", "Latest error", error, "exclamationmark.triangle.fill")
                    } else {
                        card("QUIET", "No active task", "The Agent is ready for your next instruction.", "moon.stars.fill")
                    }
                    if !session.chatHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CHAT HISTORY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(session.chatHistory.count) turns").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(session.chatHistory.suffix(12)) { turn in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(turn.role == .user ? "You" : "Agent")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(turn.content)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    card("WORKSPACE", "Contextual surfaces", "Models, providers, skills, memory and settings stay one tap away.", "circle.hexagongrid.fill")
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func card(_ eyebrow: String, _ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AgentOrb: View {
    let isActive: Bool
    let isThinking: Bool
    @State private var pulse = false

    private var accessibilityLabel: String {
        if isThinking { return "Agent thinking" }
        if isActive { return "Agent working" }
        return "Agent idle"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.78),
                            Color(red: 0.58, green: 0.66, blue: 1).opacity(0.76),
                            Color(red: 0.16, green: 0.25, blue: 0.91).opacity(0.98)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 2,
                        endRadius: 42
                    )
                )
            Circle()
                .stroke(.white.opacity(0.35), lineWidth: 1)
            Circle()
                .fill(.white.opacity(0.46))
                .frame(width: 9, height: 6)
                .blur(radius: 2.5)
                .offset(x: -10, y: -15)
        }
        .frame(width: 74, height: 74)
        .shadow(color: .black.opacity(0.25), radius: 15, y: 8)
        .scaleEffect(pulse ? (isThinking ? 1.075 : 1.045) : 1)
        .rotationEffect(.degrees(isThinking ? (pulse ? 2 : -2) : 0))
        .brightness(isThinking && pulse ? 0.035 : 0)
        .animation(
            .easeInOut(duration: isThinking ? 0.62 : (isActive ? 1.8 : 2.4))
                .repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .opacity(isActive || isThinking ? 1 : 0.94)
        .accessibilityLabel(accessibilityLabel)
    }
}
