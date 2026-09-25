import SwiftUI
import PAKernel

struct AgentScreen: View {
    @ObservedObject var session: KernelSession
    @State private var task = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSending = false
    @FocusState private var taskFocused: Bool

    private struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String

        enum Role {
            case user
            case agent
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            hero
                        } else {
                            ForEach(messages) { message in
                                messageBubble(message)
                            }
                        }

                        if isSending {
                            HStack(spacing: 10) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Agent")
                                        .font(.caption.weight(.semibold))
                                    Text(session.chatPhase ?? "Processing")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }

                        if session.executionProgress != nil || session.executionResult != nil {
                            execution
                        }

                        if let error = session.lastError {
                            errorView(error)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                taskComposer
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
            Text("Hi, I'm your Agent.")
                .font(.largeTitle.bold())
                .tracking(-0.5)
            Text("Ask anything or give me a task.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .agent { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                message.role == .user
                    ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                    : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .frame(maxWidth: 340, alignment: .leading)

            if message.role == .user { Spacer(minLength: 40) }
        }
    }

    private var taskComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Agent…", text: $task, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var execution: some View {
        DisclosureGroup("Agent activity") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.executionTrace.enumerated()), id: \.offset) { index, step in
                    executionTraceRow(step, isLast: index == session.executionTrace.count - 1)
                }

                if let result = session.executionResult {
                    Divider().padding(.vertical, 8)
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
        .font(.subheadline)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func executionTraceRow(_ step: AgentExecutionProgress, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stepIcon(step))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.footnote.weight(.semibold))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step == session.executionProgress {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, isLast ? 4 : 7)
    }

    private func stepIcon(_ step: AgentExecutionProgress) -> String {
        switch step {
        case .perception: return "text.magnifyingglass"
        case .reasoning, .reasoningCompleted: return "brain"
        case .planning: return "list.bullet.clipboard"
        case .actionProposed: return "bolt"
        case .verification: return "checkmark.shield"
        case .verificationCompleted(let accepted, _): return accepted ? "checkmark.shield.fill" : "xmark.shield.fill"
        case .executing: return "play.circle"
        case .observation: return "eye"
        case .evaluating: return "scope"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
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

    private func sendMessage() {
        let statement = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty, !isSending else { return }
        task = ""
        taskFocused = false
        messages.append(ChatMessage(role: .user, text: statement))
        isSending = true

        Task {
            let response = await session.sendChat(statement)
            await MainActor.run {
                if let response {
                    messages.append(ChatMessage(role: .agent, text: response))
                }
                isSending = false
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        Label {
            Text(message).font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
