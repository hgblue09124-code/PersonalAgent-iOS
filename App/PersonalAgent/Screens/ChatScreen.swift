import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MilestoneBanner()
                        Text("Chat submits goals to the kernel. It does not reason.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        ForEach(session.goals, id: \.id) { goal in
                            StatusRow(title: goal.status.rawValue, value: goal.statement)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("State a goal", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                    Button("Send") {
                        let statement = draft
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
