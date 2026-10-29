import SwiftUI
import PAComposition
import PAKernel

enum AgentDesign {
    static let corner: CGFloat = 22
    static let smallCorner: CGFloat = 14
    static let horizontalPadding: CGFloat = 18
    static let accent = Color(red: 0.31, green: 0.45, blue: 1.0)
    static let accentDeep = Color(red: 0.12, green: 0.18, blue: 0.52)

    static var background: some View {
        AgentDesignBackground()
    }

    static var sectionLabel: Font {
        .system(size: 12, weight: .bold, design: .rounded)
    }

    static var title: Font {
        .system(size: 30, weight: .bold, design: .rounded)
    }

    static var body: Font {
        .system(size: 15, weight: .regular, design: .rounded)
    }
}

private struct AgentDesignBackground: View {
    @AppStorage("ui.v2.enabled") private var isUIV2Enabled = false

    var body: some View {
        Group {
            if isUIV2Enabled {
                Color(.systemBackground)
            } else {
                ZStack {
                    Color(.systemGroupedBackground)
                    LinearGradient(
                        colors: [
                            AgentDesign.accent.opacity(0.11),
                            Color.clear,
                            AgentDesign.accentDeep.opacity(0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [AgentDesign.accent.opacity(0.045), .clear],
                        center: .topTrailing,
                        startRadius: 4,
                        endRadius: 240
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    let systemImage: String
    var scrollable: Bool = true
    var showsHeader: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AgentDesign.background

            Group {
                if scrollable {
                    ScrollView {
                        scaffoldContent
                    }
                    .scrollIndicators(.hidden)
                } else {
                    scaffoldContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scaffoldContent: some View {
        Group {
            if scrollable {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if showsHeader { screenHeader }
                    content()
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if showsHeader { screenHeader }
                    content()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: scrollable ? nil : .infinity, alignment: .topLeading)
        .padding(.horizontal, AgentDesign.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, scrollable ? 32 : 8)
    }

    private var screenHeader: some View {
        HStack(spacing: 12) {
            PremiumIconTile(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(AgentDesign.title)
                    .tracking(-0.7)
                Text("Personal Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

struct StatusRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentDesign.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentDesign.corner, style: .continuous)
                    .stroke(.primary.opacity(0.065), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
    }
}

struct PremiumIconTile: View {
    let systemImage: String
    var tint: Color = AgentDesign.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(tint.opacity(0.10), lineWidth: 1)
            )
    }
}

struct StatusBadge: View {
    let title: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MilestoneBanner: View {
    @Environment(\.milestoneGate) private var gate

    var body: some View {
        GlassPanel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime").font(.headline)
                    Text(bannerCopy(gate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PhaseChip(phase: .idle)
            }
        }
    }
}

private func bannerCopy(_ gate: MilestoneGate) -> String {
    if gate.skillRuntime || gate.toolRuntime {
        return "The Agent surface is connected to the runtime. Configuration stays contextual."
    }
    if gate.providers {
        return "Provider runtime is connected. Configuration stays contextual."
    }
    if gate.kernelRuntime {
        return "Kernel runtime is live. This screen does not own agent state."
    }
    return "Kernel runtime is not wired. This screen is a shell."
}

struct PhaseChip: View {
    let phase: AgentPhase

    var body: some View {
        Text(phase.rawValue)
            .font(.caption.monospaced().weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}


enum AgentMessengerTheme {
    static func accent(_ theme: String) -> Color {
        switch theme {
        case "ocean": return Color(red: 0.29, green: 0.57, blue: 0.72)
        case "emerald": return Color(red: 0.28, green: 0.58, blue: 0.42)
        default: return Color(red: 0.82, green: 0.43, blue: 0.59)
        }
    }

    static func bubbleRadius(_ style: String) -> CGFloat {
        switch style {
        case "compact": return 12
        case "round": return 24
        default: return 18
        }
    }
}

struct AgentMessengerPanel<Content: View>: View {
    @AppStorage("ui.v2.enabled") private var uiV2Enabled = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if uiV2Enabled {
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            GlassPanel { content() }
        }
    }
}
