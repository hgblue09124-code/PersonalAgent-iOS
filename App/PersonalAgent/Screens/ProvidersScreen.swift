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
                Label("Credential boundary", systemImage: "key.fill")
                    .font(.headline)
                Text("Secret material belongs to the provider security boundary and is never rendered in the Agent surface.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                    Text("Keychain-backed credential boundary").font(.caption.weight(.semibold))
                    Spacer()
                }
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
