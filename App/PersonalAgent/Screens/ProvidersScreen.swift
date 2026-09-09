import SwiftUI
import PAArchitecture

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Providers", systemImage: "server.rack") {
            MilestoneBanner()
            StatusRow(title: "selected", value: session.providerID)
            StatusRow(title: "lifecycle", value: session.providerLifecycle)
            ForEach(ArchitectureManifest.reservedProviderIDs, id: \.id) { item in
                StatusRow(title: item.id, value: item.milestone)
            }
            Text("Adapters exist behind the provider contract. Live network verification is pending. This screen does not execute providers.")
                .foregroundStyle(.secondary)
        }
    }
}
