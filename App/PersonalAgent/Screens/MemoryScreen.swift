import SwiftUI

struct MemoryScreen: View {
    @Environment(\.kernelSession) private var session
    @State private var draft = ""
    @State private var draftKind = "fact"

    // Keep choices aligned with the kinds included in contextual memory retrieval.
    private let availableKinds = [
        "fact", "preference", "context", "instruction", "semantic"
    ]

    var body: some View {
        ScreenScaffold(title: "Memory", systemImage: "brain") {
            GlassPanel {
                Label("Memory layers", systemImage: "square.stack.3d.up")
                    .font(.headline)
                Text("Persistent memory remains a contextual Agent capability.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let session {
                GlassPanel {
                    HStack {
                        Label("Stored memories", systemImage: "brain")
                            .font(.headline)
                        Spacer()
                        Text("\(session.memoryRecords.count)")
                            .font(.title3.bold())
                    }

                    ForEach(Array(session.memoryRecords.prefix(12))) { record in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.kind.capitalized)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(record.content)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(role: .destructive) {
                                Task { await session.forgetMemory(id: record.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Forget memory")
                        }
                        .padding(.vertical, 4)
                    }

                    Picker("Remember as", selection: $draftKind) {
                        ForEach(availableKinds, id: \.self) { kind in
                            Text(kind.capitalized).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        TextField("Remember something…", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Remember") {
                            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
                            let kind = draftKind
                            draft = ""
                            Task { await session.remember(value, kind: kind) }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Clear memory", role: .destructive) {
                        Task { await session.clearMemory() }
                    }
                    .buttonStyle(.bordered)
                }
            }

        }
    }

}
