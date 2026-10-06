import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var message = ""
    @State private var renameText = ""
    @State private var showRename = false
    @FocusState private var focused: Bool

    private var currentTitle: String {
        session.conversations.first(where: { $0.id == session.currentConversationID })?.title ?? "Conversation"
    }

    var body: some View {
        ScreenScaffold(title: "Chat", systemImage: "bubble.left.and.bubble.right") {
            GlassPanel {
                HStack {
                    Menu {
                        Button {
                            session.newConversation()
                        } label: {
                            Label("New conversation", systemImage: "plus")
                        }

                        if session.conversations.count > 1 {
                            Section("Conversations") {
                                ForEach(session.conversations) { conversation in
                                    Button {
                                        session.selectConversation(id: conversation.id)
                                    } label: {
                                        HStack {
                                            Text(conversation.title)
                                            if conversation.id == session.currentConversationID {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        Button {
                            renameText = currentTitle
                            showRename = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            session.deleteConversation(id: session.currentConversationID)
                        } label: {
                            Label("Delete conversation", systemImage: "trash")
                        }
                    } label: {
                        Label(currentTitle, systemImage: "bubble.left.and.bubble.right")
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        session.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                }
            }

            if !session.agentManifests.isEmpty {
                GlassPanel {
                    Menu {
                        ForEach(session.agentManifests, id: \.id) { agent in
                            Button {
                                session.selectAgent(id: agent.id)
                            } label: {
                                HStack {
                                    Text(agent.name)
                                    if agent.id == session.selectedAgentID {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Agent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.agentManifests.first(where: { $0.id == session.selectedAgentID })?.name ?? "Personal Default Agent")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select Agent")
                }
            }

            GlassPanel {
                if session.chatHistory.isEmpty {
                    ContentUnavailableView(
                        "No messages",
                        systemImage: "bubble.left",
                        description: Text("Start a conversation with the Agent.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(session.chatHistory) { turn in
                                    ChatBubble(turn: turn).id(turn.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 230, maxHeight: 430)
                        .onChange(of: session.chatHistory.count) { _, _ in
                            guard let id = session.chatHistory.last?.id else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                        }
                        .onAppear {
                            if let id = session.chatHistory.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }

            GlassPanel {
                HStack(spacing: 10) {
                    TextField("Message Agent…", text: $message, axis: .vertical)
                        .focused($focused)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        message = ""
                        Task { await session.submitGoal(value) }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                session.renameCurrentConversation(renameText)
            }
        }
    }
}


private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if turn.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(.tint.opacity(0.10), in: Circle())
                bubble
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble
                Image(systemName: "person.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.secondary.opacity(0.10), in: Circle())
            }
        }
    }

    private var bubble: some View {
        Text(turn.content)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: 310, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                turn.role == .assistant
                    ? AnyShapeStyle(.thinMaterial)
                    : AnyShapeStyle(Color.accentColor.opacity(0.13)),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
    }
}
