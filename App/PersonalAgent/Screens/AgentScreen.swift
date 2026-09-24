import SwiftUI
import PAKernel

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var task = ""
    @FocusState private var taskFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    taskComposer
                    activity
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
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.largeTitle.bold())
                .tracking(-0.5)
            Text("Tell me what you want to get done.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Ask Agent to do something…", text: $task, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(3...6)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit { runTask() }

            HStack {
                Text("Agent will use the available runtime capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    runTask()
                } label: {
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

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text(session.state.lifecycle.rawValue.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if let goal = session.state.activeGoalID {
                Label("Working on \(goal.rawValue)", systemImage: "circle.dotted")
                    .font(.subheadline)
            } else {
                Label("Ready for a task", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                StatusRow(title: "Phase", value: session.state.phase.rawValue)
                StatusRow(title: "Runtime", value: session.milestone.kernelRuntime ? "Ready" : "Unavailable")
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
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
        case "running":
            return "I’m working."
        case "paused":
            return "I’m paused."
        case "stopped":
            return "Ready when you are."
        default:
            return "What can I do for you?"
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
            Text(message)
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
