import SwiftUI
import PAComposition
import PAKernel

struct ScreenScaffold<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                        Text(title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct MilestoneBanner: View {
    @Environment(\.milestoneGate) private var gate

    var body: some View {
        GlassPanel {
            Text("Runtime")
                .font(.headline)
            Text(bannerCopy(gate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                PhaseChip(phase: .idle)
                Spacer()
                Text("Connected surface")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
