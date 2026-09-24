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
                        Label {
                            Text(error)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
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

                Section("Local AI") {
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
                        Label("Import GGUF", systemImage: "square.and.arrow.down")
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

    var body: some View {
        List {
            Section("Current Provider") {
                LabeledContent("Provider", value: session.providerID)
                LabeledContent("Status", value: session.providerLifecycle.capitalized)
            }
        }
        .navigationTitle("Provider")
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