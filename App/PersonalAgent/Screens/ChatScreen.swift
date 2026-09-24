import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(session.goals, id: \.id) { goal in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(goal.statement)
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                Text(goal.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let progress = session.executionProgress {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(progress.title, systemImage: "sparkles")
                                    .font(.headline)
                                Text(progress.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }

                        if let result = session.executionResult {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Agent result", systemImage: "checkmark.circle")
                                    .font(.headline)
                                Text(result)
                                    .textSelection(.enabled)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message Agent…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                    Button("Send") {
                        let statement = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !statement.isEmpty else { return }
                        draft = ""
                        Task { await session.submitGoal(statement) }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Chat")
        }
    }
}
