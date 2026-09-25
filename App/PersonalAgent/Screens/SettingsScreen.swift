import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAArchitecture

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImportingGGUF = false
    @State private var lastImportError: String?

    var body: some View {
        NavigationStack {
            List {
                if let error = session.lastError ?? lastImportError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.footnote)
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section("Agent") {
                    NavigationLink {
                        RuntimeSettingsView(session: session)
                    } label: {
                        Label("Runtime", systemImage: "cpu")
                    }

                    NavigationLink {
                        ProviderSettingsView(session: session)
                    } label: {
                        Label("Provider", systemImage: "server.rack")
                    }

                    NavigationLink {
                        SkillSettingsView(session: session)
                    } label: {
                        Label("Skills", systemImage: "puzzlepiece")
                    }
                }

                Section {
                    HStack {
                        Label("Active Model", systemImage: "cube.box")
                        Spacer()
                        Text(session.activeModelDescriptor?.name ?? "None")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        isImportingGGUF = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import GGUF")
                        }
                    }

                    Button {
                        Task { await session.downloadDevModel() }
                    } label: {
                        Label(
                            session.isDownloadingDevModel ? "Downloading…" : "Download Dev Model",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(session.isDownloadingDevModel)
                } header: {
                    Text("Local AI")
                }
                Section("System") {
                    HStack {
                        Label("Storage", systemImage: "externaldrive")
                        Spacer()
                        Text("Local-first")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Target", systemImage: "iphone")
                        Spacer()
                        Text("iPhone")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Interface")
                        Spacer()
                        Text("Native SwiftUI")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassScreenBackground())
            .navigationTitle("Settings")
        }
        .fileImporter(
            isPresented: $isImportingGGUF,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                lastImportError = nil
                Task { await session.importModel(from: selectedURL) }
            case .failure(let error):
                lastImportError = error.localizedDescription
            }
        }
    }
}

private struct RuntimeSettingsView: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        List {
            Section("Current State") {
                LabeledContent("Lifecycle", value: session.state.lifecycle.rawValue.capitalized)
                LabeledContent("Phase", value: session.state.phase.rawValue.capitalized)
                LabeledContent("Local Model", value: modelState)
            }
        }
        .navigationTitle("Runtime")
    }

    private var modelState: String {
        switch session.activeEngineState {
        case .unloaded: return "Unloaded"
        case .loading: return "Loading"
        case .loaded: return "Loaded"
        case .unloading: return "Unloading"
        case .failed: return "Failed"
        }
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var session: KernelSession
    @State private var apiKey = ""
    @State private var hasAPIKey = false
    @State private var isSaving = false

    var body: some View {
        List {
            Section("Current Provider") {
                LabeledContent("Provider", value: session.providerID)
                LabeledContent("Status", value: session.providerLifecycle.capitalized)
                LabeledContent("API Key", value: hasAPIKey ? "Configured" : "Not configured")
            }

            Section("OpenAI") {
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task {
                        isSaving = true
                        await session.configureProviderAPIKey(apiKey)
                        apiKey = ""
                        hasAPIKey = await session.hasProviderAPIKey()
                        isSaving = false
                    }
                } label: {
                    Label(isSaving ? "Saving…" : "Save API Key", systemImage: "key.fill")
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                if hasAPIKey {
                    Button(role: .destructive) {
                        Task {
                            await session.removeProviderAPIKey()
                            hasAPIKey = await session.hasProviderAPIKey()
                        }
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                }

                Text("The key is stored in the iOS Keychain and is never shown in Agent Thinking or logs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Provider")
        .task {
            hasAPIKey = await session.hasProviderAPIKey()
        }
    }
}

private struct SkillSettingsView: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        List {
            Section("Capabilities") {
                LabeledContent("Available", value: "\(session.moduleIDs.count)")
            }
        }
        .navigationTitle("Skills")
    }
}