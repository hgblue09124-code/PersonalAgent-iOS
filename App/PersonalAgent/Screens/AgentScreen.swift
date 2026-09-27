import SwiftUI
import PAKernel
import PARuntime

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var task = ""
    @FocusState private var taskFocused: Bool

    var body: some View {
        ZStack {
            background
            content
        }
        .toolbar(.hidden, for: .navigationBar)
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
            Spacer(minLength: 24)
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

            lifecycleMenu
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            AgentOrb(
                isActive: session.state.lifecycle.rawValue.lowercased() == "running",
                isThinking: session.executionProgress != nil
            )

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
        } else if let result = session.executionResult {
            statusCard(title: "Done", detail: result, symbol: "checkmark.circle.fill")
        } else if let error = session.lastError {
            statusCard(title: "Something went wrong", detail: error, symbol: "exclamationmark.triangle.fill")
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

private struct AgentOrb: View {
    let isActive: Bool
    let isThinking: Bool
    @State private var pulse = false

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
        .scaleEffect(pulse ? 1.045 : 1)
        .animation(
            .easeInOut(duration: isThinking ? 0.7 : 2.2).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .opacity(isActive || isThinking ? 1 : 0.94)
        .accessibilityLabel(isThinking ? "Agent thinking" : "Agent")
    }
}
