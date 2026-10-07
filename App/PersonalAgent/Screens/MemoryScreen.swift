import SwiftUI

struct MemoryScreen: View {
    @Environment(\.kernelSession) private var session
    @State private var draft = ""

    private let reservedKinds = [
        "working", "episodic", "semantic", "preference", "procedural"
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

                    HStack {
                        TextField("Remember something…", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Remember") {
                            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
                            draft = ""
                            Task { await session.remember(value) }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Clear memory", role: .destructive) {
                        Task { await session.clearMemory() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            ForEach(reservedKinds, id: \.self) { kind in
                GlassPanel {
                    HStack {
                        Label(LocalizedStringKey(memoryTitle(kind)), systemImage: memoryIcon(kind))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("supported")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func memoryTitle(_ kind: String) -> String {
        switch kind {
        case "working": return "Working"
        case "episodic": return "Episodic"
        case "semantic": return "Semantic"
        case "preference": return "Preference"
        default: return "Procedural"
        }
    }

    private func memoryIcon(_ kind: String) -> String {
        switch kind {
        case "working": return "bolt.fill"
        case "episodic": return "clock.arrow.circlepath"
        case "semantic": return "brain.head.profile"
        case "preference": return "slider.horizontal.3"
        default: return "arrow.triangle.2.circlepath"
        }
    }
}
