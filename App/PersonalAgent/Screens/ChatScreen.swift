import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var message = ""
    @State private var renameText = ""
    @State private var showRename = false
    @FocusState private var focused: Bool

    private var currentTitle: String { session.conversations.first(where: { $0.id == session.currentConversationID })?.title ?? "Conversation" }

    var body: some View {
        ScreenScaffold(title: "Chat", systemImage: "bubble.left.and.bubble.right") {
            conversationHeader
            agentPicker
            messages
            composer
        }
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.renameCurrentConversation(renameText) }
        }
    }

    private var conversationHeader: some View {
        GlassPanel {
            HStack(spacing: 12) {
                PremiumIconTile(systemImage: "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTitle).font(.headline).lineLimit(1)
                    Text("\(session.chatHistory.count) turns").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button { session.newConversation() } label: { Label("New conversation", systemImage: "plus") }
                    Button { renameText = currentTitle; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    if session.conversations.count > 1 {
                        Section("Conversations") {
                            ForEach(session.conversations) { conversation in
                                Button { session.selectConversation(id: conversation.id) } label: {
                                    HStack { Text(conversation.title); if conversation.id == session.currentConversationID { Spacer(); Image(systemName: "checkmark") } }
                                }
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { session.deleteConversation(id: session.currentConversationID) } label: { Label("Delete conversation", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .disabled(session.isSubmitting)
            }
        }
    }

    @ViewBuilder private var agentPicker: some View {
        if !session.agentManifests.isEmpty {
            GlassPanel {
                Menu {
                    ForEach(session.agentManifests, id: \.id) { agent in
                        Button { session.selectAgent(id: agent.id) } label: { HStack { Text(agent.name); if agent.id == session.selectedAgentID { Spacer(); Image(systemName: "checkmark") } } }
                    }
                } label: {
                    HStack(spacing: 10) {
                        PremiumIconTile(systemImage: "person.crop.circle.badge.checkmark")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Agent").font(.caption).foregroundStyle(.secondary)
                            Text(session.agentManifests.first(where: { $0.id == session.selectedAgentID })?.name ?? "Personal Default Agent").font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var messages: some View {
        GlassPanel {
            if session.chatHistory.isEmpty {
                VStack(spacing: 12) {
                    PremiumIconTile(systemImage: "sparkles")
                    Text("Start a conversation").font(.headline)
                    Text("Ask the Agent to explain, plan, create or act.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 44)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(session.chatHistory) { turn in ChatBubble(turn: turn).id(turn.id) }
                            if !session.streamingResponse.isEmpty {
                                StreamingChatBubble(content: session.streamingResponse).id("streaming-response")
                            }
                        }.padding(.vertical, 4)
                    }
                    .frame(minHeight: 260, maxHeight: 500)
                    .onChange(of: session.chatHistory.count) { _, _ in if let id = session.chatHistory.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } } }
                    .onChange(of: session.streamingResponse) { _, value in
                        if !value.isEmpty { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("streaming-response", anchor: .bottom) } }
                    }
                    .onAppear { if let id = session.chatHistory.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
    }

    private var composer: some View {
        GlassPanel {
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Message your Agent…", text: $message, axis: .vertical).focused($focused).textFieldStyle(.plain).lineLimit(1...5).submitLabel(.send).onSubmit(send)
                if session.isSubmitting {
                    Button(action: session.cancelCurrentGeneration) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel("Stop response generation")
                    .accessibilityHint("Cancels the current Agent request")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                }
            }
            if session.isSubmitting {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(session.streamingResponse.isEmpty ? "Agent is thinking…" : "Generating response…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let metrics = session.responseMetrics {
                        Text("~\(metrics.estimatedOutputTokens) tokens · \(metrics.estimatedTokensPerSecond, specifier: "%.1f") tok/s")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else if let metrics = session.responseMetrics {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").foregroundStyle(.secondary)
                    Text("Last response · ~\(metrics.estimatedOutputTokens) tokens · \(metrics.estimatedTokensPerSecond, specifier: "%.1f") tok/s")
                    if let ttft = metrics.timeToFirstToken {
                        Text("· first token \(ttft, specifier: "%.2f")s")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func send() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !session.isSubmitting else { return }
        message = ""; focused = false
        Task { await session.submitGoal(value) }
    }
}

private struct StreamingChatBubble: View {
    let content: String
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PremiumIconTile(systemImage: "sparkles")
            Text(content + "▍")
                .font(.body).textSelection(.enabled).frame(maxWidth: 310, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(AnyShapeStyle(.thinMaterial), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.045), lineWidth: 1))
            Spacer(minLength: 18)
        }
    }
}

private struct ChatBubble: View {
    let turn: ChatTurn
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if turn.role == .assistant {
                PremiumIconTile(systemImage: "sparkles")
                bubble
                Spacer(minLength: 18)
            } else {
                Spacer(minLength: 18)
                bubble
                PremiumIconTile(systemImage: "person.fill", tint: .secondary)
            }
        }
    }
    private var bubble: some View {
        Text(turn.content).font(.body).textSelection(.enabled).frame(maxWidth: 310, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(turn.role == .assistant ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(AgentDesign.accent.opacity(0.11)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.045), lineWidth: 1))
    }
}
