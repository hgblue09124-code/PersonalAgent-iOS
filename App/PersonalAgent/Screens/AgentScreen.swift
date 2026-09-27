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

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    hero
                    taskComposer

                    if let progress = session.executionProgress {
                        progressView(progress)
                            .padding(.top, 16)
                    }

                    if let result = session.executionResult {
                        resultView(result)
                            .padding(.top, 16)
                    }

                    if let error = session.lastError {
                        errorView(error)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.11, green: 0.18, blue: 0.88),
                Color(red: 0.08, green: 0.13, blue: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "circle.grid.2x2.fill")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            lifecycleMenu
        }
        .padding(.vertical, 8)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            AgentOrb(
                isActive: session.state.lifecycle.rawValue.lowercased() == "running",
                isThinking: session.executionProgress != nil
            )
            .padding(.top, 22)
            .padding(.bottom, 18)

            Text(greeting)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Tell me what you want to get done.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    private var taskComposer: some View {
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

            Button { runTask() } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
            }
            .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Run Agent")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private func progressView(_ progress: AgentExecutionProgress) -> some View {
        statusCard(title: progress.title, detail: progress.detail, symbol: "sparkles")
    }

    private func resultView(_ result: String) -> some View {
        statusCard(title: "Result", detail: result, symbol: "checkmark.circle.fill")
    }

    private func statusCard(title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                .background(.white.opacity(0.12), in: Circle())
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

    private func errorView(_ message: String) -> some View {
        Label {
            Text(message).font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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
                            .white.opacity(0.72),
                            Color(red: 0.58, green: 0.66, blue: 1.0).opacity(0.72),
                            Color(red: 0.16, green: 0.25, blue: 0.91).opacity(0.98)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 2,
                        endRadius: 82
                    )
                )

            Circle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
                .blur(radius: 0.4)

            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 16, height: 9)
                .blur(radius: 3)
                .offset(x: -14, y: -22)
        }
        .frame(width: 116, height: 116)
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
        .scaleEffect(pulse ? 1.035 : 1)
        .animation(
            .easeInOut(duration: isThinking ? 0.8 : 2.4).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .opacity(isActive || isThinking ? 1 : 0.94)
        .accessibilityLabel(isThinking ? "Agent thinking" : "Agent")
    }
}
