import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var message = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScreenScaffold(title: "Chat", systemImage: "bubble.left.and.bubble.right") {
            GlassPanel {
                Label("Talk to Agent", systemImage: "sparkles")
                    .font(.headline)
                Text("The Agent home surface is the primary conversation entry point. Use this screen for a focused chat context.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                HStack(spacing: 10) {
                    TextField("Message Agent…", text: $message)
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
    }
}
