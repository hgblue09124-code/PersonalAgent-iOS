import SwiftUI
import PAArchitecture
import PAFoundation

struct GlassScreenBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            Circle()
                .fill(Color.accentColor.opacity(0.055))
                .frame(width: 230, height: 230)
                .blur(radius: 65)
                .offset(x: 150, y: -300)

            Circle()
                .fill(Color.secondary.opacity(0.035))
                .frame(width: 210, height: 210)
                .blur(radius: 70)
                .offset(x: -145, y: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(GlassScreenBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}

struct MilestoneBanner: View {
    @Environment(\.milestoneGate) private var gate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Milestone \(gate.milestone)")
                .font(.headline)
            Text(bannerCopy(gate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                PhaseChip(phase: .idle)
                Text("phase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func bannerCopy(_ gate: MilestoneGate) -> String {
    if gate.skillRuntime || gate.toolRuntime {
        return "Kernel, provider, and module runtime are wired. This screen does not own execution."
    }
    if gate.providers {
        return "Kernel and provider runtime are wired. This screen does not own execution."
    }
    if gate.kernelRuntime {
        return "Kernel runtime is live. This screen does not own agent state."
    }
    return "Kernel runtime is not wired. This screen is a shell, not an agent."
}

struct PhaseChip: View {
    let phase: AgentPhase

    var body: some View {
        Text(phase.rawValue)
            .font(.caption.monospaced())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
