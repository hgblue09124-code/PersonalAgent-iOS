import SwiftUI
import PAArchitecture

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.providerID)
                                .font(.headline)
                            Text(providerSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Available") {
                    ForEach(ArchitectureManifest.reservedProviderIDs, id: .id) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.id)
                                Text(item.milestone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("Provider configuration and connection controls appear here as each provider becomes available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Providers")
        }
    }

    private var providerSubtitle: String {
        switch session.providerLifecycle.lowercased() {
        case "running": return "Active and ready"
        case "configured": return "Configured"
        default: return session.providerLifecycle.capitalized
        }
    }
}