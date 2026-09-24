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

                Section("Remote Models") {
                    if session.providerModels.isEmpty {
                        Text("No remote models discovered. Configure an API key and refresh.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.providerModels, id: \.id) { model in
                            Button {
                                Task { await session.selectProviderModel(id: model.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .foregroundStyle(.primary)
                                        Text(model.id.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.id == session.selectedProviderModelID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }

                        Button {
                            Task { await session.refreshProviderModels() }
                        } label: {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Available Providers") {
                    ForEach(ArchitectureManifest.reservedProviderIDs, id: \.id) { item in
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
        .task { await session.refreshProviderModels() }
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