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
                        Label(LocalizedStringKey(memoryTitle(kind)), systemImage: memoryIcon(kind))
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
