import SwiftUI
import PAKernel

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var task = ""
    @FocusState private var taskFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    taskComposer
                    execution
                    if let error = session.lastError {
                        errorView(error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Agent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    lifecycleMenu
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.bold())
                .tracking(-0.5)
            Text("Tell me what you want to get done.")
                .foregroundStyle(.secondary)
        }
    }

    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Ask Agent to do something…", text: $task, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit(runTask)

            HStack {
                Text("The Agent will use available capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: runTask) {
                    Image(systemName: "arrow.up")
                        .font(.headline.bold())
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Run Agent")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var execution: some View {
        if session.executionResult != nil || session.executionProgress != nil {
            executionSession
        } else {
            emptyActivity
        }
    }

    private var emptyActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ready", systemImage: "checkmark.circle")
                .font(.headline)
            Text("Give the Agent a task to begin.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var executionSession: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progress = session.executionProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.title)
                            .font(.headline)
                        Text(progress.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let result = session.executionResult {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result")
                        .font(.headline)
                    Text(result)
                        .textSelection(.enabled)
                }
            }

            if session.executionResult != nil {
                HStack {
                    Button("New Task", action: resetTask)
                        .buttonStyle(.bordered)
                    Button("Retry", action: retryTask)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var lifecycleMenu: some View {
        Menu {
            Button("Start") { Task { await session.start() } }
            Button("Pause") { Task { await session.pause() } }
            Button("Resume") { Task { await session.resume() } }
            Button("Stop", role: .destructive) { Task { await session.stop() } }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Agent runtime controls")
    }

    private var greeting: String {
        switch session.state.lifecycle.rawValue.lowercased() {
        case "running": return "I'm working."
        case "paused": return "I'm paused."
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

    private func retryTask() {
        Task { await session.retryTask() }
    }

    private func resetTask() {
        session.resetTask()
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