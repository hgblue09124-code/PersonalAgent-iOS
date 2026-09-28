import SwiftUI
import PAKernel
import PARuntime

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var task = ""
    @State private var showAgentPanel = false
    @State private var appeared = false
    @State private var showActivity = false
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
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appeared = true } }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.106, green: 0.184, blue: 0.878),
                Color(red: 0.075, green: 0.110, blue: 0.520)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 18)
            quickActions
            Spacer(minLength: 12)
            hero
            Spacer(minLength: 22)
            composer
            status
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var topBar: some View {
        HStack {
            Text("PERSONAL AGENT")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.82))

            Spacer()

            HStack(spacing: 8) {
                Button { showActivity = true } label: { topButton("waveform.path.ecg") }
                lifecycleMenu
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickAction("New task", "plus") { taskFocused = true }
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
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func topButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(.white.opacity(0.10), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
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

            Text(greeting)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .tracking(-1.1)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Tell me what you want to get done.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
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
        .background(.black.opacity(0.27), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.17), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    @ViewBuilder
    private var status: some View {
        if let progress = session.executionProgress {
            statusCard(title: progress.title, detail: progress.detail, symbol: "sparkles")
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let result = session.executionResult {
            statusCard(title: "Done", detail: result, symbol: "checkmark.circle.fill")
                .transition(.scale(scale: 0.96).combined(with: .opacity))
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
                Text(title).font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 12)
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
            Text(title).foregroundStyle(.secondary)
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
