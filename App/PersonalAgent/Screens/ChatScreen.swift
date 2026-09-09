import SwiftUI

struct ChatScreen: View {
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MilestoneBanner()
                        Text("Chat is an input surface for goals. It is not the agent.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Goal goes here after M1", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .disabled(true)
                    Button("Send") {}
                        .disabled(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Chat")
        }
    }
}
