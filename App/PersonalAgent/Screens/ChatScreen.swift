import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var message = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScreenScaffold(title: "Chat", systemImage: "bubble.left.and.bubble.right") {
            if session.chatMessages.isEmpty {
                GlassPanel {
                    Label("Talk to Agent", systemImage: "sparkles").font(.headline)
                    Text("Conversation history is saved automatically and available through the Memory skill.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                GlassPanel {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(session.chatMessages) { item in
                                    HStack {
                                        if item.role == .user { Spacer(minLength: 24) }
                                        VStack(alignment: item.role == .user ? .trailing : .leading, spacing: 4) {
                                            Text(item.role == .user ? "You" : "Agent")
                                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                            Text(item.content).textSelection(.enabled)
                                        }
                                        .padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                        if item.role != .user { Spacer(minLength: 24) }
                                    }.id(item.id)
                                }
                            }
                        }
                        .frame(maxHeight: 430)
                        .onChange(of: session.chatMessages.count) { _, _ in
                            if let last = session.chatMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }

            if let error = session.lastError {
                GlassPanel { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption) }
            }

            GlassPanel {
                HStack(spacing: 10) {
                    TextField("Message Agent…", text: $message)
                        .focused($focused).textFieldStyle(.roundedBorder)
                        .onSubmit { submit() }
                    Button(action: submit) { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderedProminent)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        message = ""
        Task { await session.submitGoal(value) }
    }
}
