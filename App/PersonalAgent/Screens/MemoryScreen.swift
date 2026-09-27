import SwiftUI

struct MemoryScreen: View {
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

            ForEach(reservedKinds, id: \.self) { kind in
                GlassPanel {
                    HStack {
                        Text(kind.capitalized)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("contract")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
