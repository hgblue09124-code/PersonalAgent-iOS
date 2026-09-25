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
            ZStack {
                AgentBackground()

                conversation
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        resetConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.medium))
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
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
                    .accessibilityElement(children: .combine)
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
                LazyVStack(spacing: 22) {
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

                    Color.clear.frame(height: 18)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)
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
        VStack(spacing: 24) {
            Spacer(minLength: 44)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 76, height: 76)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
                        }

                    Image(systemName: "sparkles")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(.tint)
                }

                VStack(spacing: 7) {
                    Text("What can I help with?")
                        .font(.title2.weight(.semibold))
                        .tracking(-0.2)

                    Text("Ask a question, explore an idea, or give your Agent a task.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                }
            }

            VStack(spacing: 9) {
                suggestion("What can you do?", systemImage: "sparkles")
                suggestion("2 + 2 = ?", systemImage: "function")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.bottom, 30)
    }

    private func suggestion(_ text: String, systemImage: String) -> some View {
        Button {
            task = text
            taskFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 360)
            .frame(height: 46)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        Group {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 42)

                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            } else {
                HStack(alignment: .top, spacing: 11) {
                    agentAvatar

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Agent")
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

                    Spacer(minLength: 18)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var agentAvatar: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .frame(width: 30, height: 30)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
            }
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 11) {
            agentAvatar

            VStack(alignment: .leading, spacing: 7) {
                Text("Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(.secondary.opacity(0.75))

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
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Message Agent", text: $task, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...7)
                .focused($taskFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .accessibilityLabel("Message Agent")

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(sendButtonBackground, in: Circle())
                    .foregroundStyle(sendButtonForeground)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.leading, 16)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .background(.clear)
    }

    private var canSend: Bool {
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var sendButtonBackground: some ShapeStyle {
        canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.15))
    }

    private var sendButtonForeground: some ShapeStyle {
        canSend ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary)
    }

    @ViewBuilder
    private var execution: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.executionTrace.enumerated()), id: \.offset) { index, step in
                    executionTraceRow(step, isLast: index == session.executionTrace.count - 1)
                }

                if let result = session.executionResult {
                    Divider().padding(.vertical, 9)

                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 7)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.tint)
                Text("Agent activity")
                    .font(.subheadline.weight(.medium))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.6)
        }
    }

    private func executionTraceRow(_ step: AgentExecutionProgress, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stepIcon(step))
                .font(.caption.weight(.semibold))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.footnote.weight(.semibold))

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

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
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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
            Text(message)
                .font(.footnote)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.red.opacity(0.22), lineWidth: 0.7)
        }
    }
}

private struct AgentBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            Circle()
                .fill(Color.accentColor.opacity(0.07))
                .frame(width: 250, height: 250)
                .blur(radius: 65)
                .offset(x: 125, y: -270)

            Circle()
                .fill(Color.secondary.opacity(0.045))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -140, y: 250)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
