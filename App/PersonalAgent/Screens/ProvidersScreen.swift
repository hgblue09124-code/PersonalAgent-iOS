import SwiftUI

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Providers", systemImage: "server.rack") {
            StatusRow(title: "selected", value: session.providerID)
            StatusRow(title: "lifecycle", value: session.providerLifecycle)
            Text("Adapters exist behind the provider contract. Live network verification is pending. This screen does not execute providers.")
                .foregroundStyle(.secondary)
        }
    }
}
