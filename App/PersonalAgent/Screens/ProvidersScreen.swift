import SwiftUI

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Providers", systemImage: "server.rack") {
            GlassPanel {
                Label("Active provider", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                StatusRow(title: "Provider", value: session.providerID)
                StatusRow(title: "Lifecycle", value: session.providerLifecycle)
                StatusRow(title: "Connection", value: session.providerLifecycle.lowercased().contains("error") ? "Attention" : "Available")
            }

            GlassPanel {
                Label("Provider contract", systemImage: "link")
                    .font(.headline)
                Text("Providers are adapters behind the Agent contract. This surface reports configuration without owning execution.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
