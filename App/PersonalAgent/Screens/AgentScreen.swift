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
            ZStack(alignment: .bottom) {
                conversation
                composer
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        resetConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Personal Agent")
                            .font(.subheadline.weight(.semibold))
                        Text(session.selectedProviderModelID?.rawValue ?? "Local Agent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    lifecycleMenu
                }
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if messages.isEmpty {
                        welcome
                    }

                    ForEach(messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if isSending {
                        thinkingRow
                            .id("thinking")
                    }

                    if session.executionProgress != nil || session.executionResult != nil {
                        execution
                    }

                    if let error = session.lastError {
                        errorView(error)
                    }

                    Color.clear.frame(height: 86)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isSending) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 6) {
                Text("What can I help with?")
                    .font(.title2.weight(.bold))
                Text("Chat with your Agent. Ask a question or give it a task.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                suggestion("What can you do?")
                suggestion("2 + 2 = ?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            task = text
            taskFocused = true
        } label: {
            Text(text)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .agent {
                agentAvatar
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }

            if message.role == .user {
                Spacer(minLength: 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.leading, message.role == .user ? 44 : 0)
        .padding(.trailing, message.role == .agent ? 22 : 0)
    }

    private var agentAvatar: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.bold))
            .frame(width: 30, height: 30)
            .background(.tint.opacity(0.12), in: Circle())
            .foregroundStyle(.tint)
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            agentAvatar

            VStack(alignment: .leading, spacing: 7) {
                Text("Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    Circle().frame(width: 6, height: 6)
                    Circle().frame(width: 6, height: 6)
                    Circle().frame(width: 6, height: 6)
                }
                .foregroundStyle(.secondary)
                .opacity(0.7)

                if let phase = session.chatPhase {
                    Text(phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Agent", text: $task, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...7)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(
                        task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                            ? AnyShapeStyle(Color.secondary.opacity(0.16))
                            : AnyShapeStyle(Color.accentColor),
                        in: Circle()
                    )
                    .foregroundStyle(
                        task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                            ? Color.secondary
                            : Color.white
                    )
            }
            .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.quaternary, lineWidth: 0.7)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                Text(step.title).font(.footnote.weight(.semibold))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if step == session.executionProgress {
                ProgressView().controlSize(.mini)
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

    private func resetConversation() {
        messages.removeAll()
        session.resetTask()
        task = ""
        isSending = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if let last = messages.last {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            } else if isSending {
                proxy.scrollTo("thinking", anchor: .bottom)
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
