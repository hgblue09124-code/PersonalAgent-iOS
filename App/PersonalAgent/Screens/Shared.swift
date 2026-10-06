import SwiftUI
import PAComposition
import PAKernel

enum AgentDesign {
    static let corner: CGFloat = 24
    static let horizontalPadding: CGFloat = 20
    static let accent = Color(red: 0.30, green: 0.46, blue: 1.0)
    static let accentDeep = Color(red: 0.12, green: 0.18, blue: 0.52)

    static var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [accent.opacity(0.10), Color.clear, accentDeep.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AgentDesign.background
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentDesign.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screenHeader: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AgentDesign.accent)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AgentDesign.accent.opacity(0.14), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text("Personal Agent")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentDesign.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentDesign.corner, style: .continuous)
                    .stroke(.primary.opacity(0.065), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.055), radius: 22, y: 10)
    }
}

struct PremiumIconTile: View {
    let systemImage: String
    var tint: Color = AgentDesign.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StatusBadge: View {
    let title: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title).font(.caption.weight(.bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

struct MilestoneBanner: View {
    @Environment(\.milestoneGate) private var gate

    var body: some View {
        GlassPanel {
            Text("Runtime").font(.headline)
            Text(bannerCopy(gate)).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                PhaseChip(phase: .idle)
                Spacer()
                Text("Connected surface").font(.caption).foregroundStyle(.secondary)
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
