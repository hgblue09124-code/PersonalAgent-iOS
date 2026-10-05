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

            GlassPanel {
                if session.chatHistory.isEmpty {
                    ContentUnavailableView(
                        "No messages",
                        systemImage: "bubble.left",
                        description: Text("Start a conversation with the Agent.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(session.chatHistory) { turn in
                                HStack {
                                    if turn.role == .assistant {
                                        Text(turn.content)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer(minLength: 30)
                                    } else {
                                        Spacer(minLength: 30)
                                        Text(turn.content)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
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
