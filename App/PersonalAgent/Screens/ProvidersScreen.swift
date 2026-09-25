import SwiftUI
import PAArchitecture
import PAComposition

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Provider Route") {
                    Picker("Route", selection: Binding(
                        get: { session.providerRoute },
                        set: { route in
                            Task { await session.selectProviderRoute(route) }
                        }
                    )) {
                        Text("Remote").tag(ProviderRoute.remote)
                        Text("Local").tag(ProviderRoute.local)
                    }
                    .pickerStyle(.segmented)

                    Text(session.providerRoute == .remote
                         ? "Chat uses the configured remote provider."
                         : "Chat uses the active GGUF local model. No remote fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.providerRoute == .remote {
                    Section("Remote API") {
                        SecureField("OpenAI API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        HStack {
                            Button("Save API Key") {
                                let value = apiKey
                                Task {
                                    await session.configureProviderAPIKey(value)
                                    apiKey = ""
                                }
                            }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Button("Remove Key", role: .destructive) {
                                Task { await session.removeProviderAPIKey() }
                            }
                        }

                        Text("The key is stored in the iOS Keychain. It is not shown after saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Active Provider") {
                    HStack {
                        Image(systemName: session.providerRoute == .local ? "cpu" : "server.rack")
                            .font(.title2)
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.providerID)
                                .font(.headline)
                            Text(connectionDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        connectionIcon
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task { await session.testProviderConnection() }
                    } label: {
                        Label(
                            session.providerConnectionState == "Testing…" ? "Testing Connection…" : "Test Connection",
                            systemImage: "bolt.horizontal.circle"
                        )
                    }
                    .disabled(session.providerConnectionState == "Testing…")

                    Text("Connected means a real provider request succeeded. A saved API key alone is not considered connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(session.providerRoute == .remote ? "Remote Models" : "Active Local Model") {
                    if session.providerModels.isEmpty {
                        Text(session.providerRoute == .remote
                             ? "No models available. Configure the provider and test the connection."
                             : "No active local model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.providerModels, id: \.id) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .foregroundStyle(.primary)
                                    Text(model.id.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if session.providerRoute == .remote,
                                   model.id == session.selectedProviderModelID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard session.providerRoute == .remote else { return }
                                Task { await session.selectProviderModel(id: model.id) }
                            }
                        }

                        Button {
                            Task { await session.refreshProviderModels() }
                        } label: {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Provider Ecosystem") {
                    ForEach(ArchitectureManifest.reservedProviderIDs, id: \.id) { item in
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.id)
                                    Text(item.milestone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.id == session.providerID ? "checkmark.circle.fill" : "circle")
                            }

                            Spacer()

                            Text(item.id == session.providerID ? session.providerConnectionState : "Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassScreenBackground())
            .navigationTitle("Providers")
            .task {
                await session.refresh()
                if await session.hasProviderAPIKey() {
                    apiKey = ""
                }
                await session.refreshProviderModels()
            }
        }
    }

    private var connectionDescription: String {
        switch session.providerConnectionState {
        case "Connected":
            return "Connected and verified"
        case "Testing…":
            return "Checking live connectivity…"
        case "Connection failed":
            return "Connection failed — check credentials/network"
        case "Not configured":
            return "API key not configured"
        default:
            return "Connection not yet verified"
        }
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch session.providerConnectionState {
        case "Connected":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "Testing…":
            ProgressView()
        case "Connection failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case "Not configured":
            Image(systemName: "key.slash")
                .foregroundStyle(.secondary)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}
