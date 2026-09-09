import SwiftUI
import PAArchitecture

struct ProvidersScreen: View {
    var body: some View {
        ScreenScaffold(title: "Providers", systemImage: "server.rack") {
            MilestoneBanner()
            ForEach(ArchitectureManifest.reservedProviderIDs, id: \.id) { item in
                StatusRow(title: item.id, value: item.milestone)
            }
            Text("Provider implementations are not present. Kernel does not import provider modules.")
                .foregroundStyle(.secondary)
        }
    }
}
