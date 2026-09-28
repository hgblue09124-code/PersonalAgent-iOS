import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAComposition

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImportingGGUF = false
    @State private var lastImportError: String?

    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gearshape") {
            if let error = session.lastError ?? lastImportError {
                GlassPanel {
                    Label("Attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            GlassPanel {
                HStack {
                    Label("Active model", systemImage: "cube.box")
                        .font(.headline)
                    Spacer()
                    LifecycleStateBadge(state: session.activeEngineState)
                }

                Text(session.activeModelDescriptor?.name ?? "No model selected")
                    .font(.subheadline.weight(.semibold))

                if let active = session.activeModelDescriptor {
                    HStack {
                        Button(session.activeEngineState == .loaded ? "Unload" : "Load") {
                            Task {
                                if session.activeEngineState == .loaded {
                                    await session.unloadActiveModel()
                                } else {
                                    await session.loadActiveModel()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Deselect", role: .destructive) {
                            Task { await session.selectActiveModel(id: nil) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Import a GGUF model or download the small development model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GlassPanel {
                HStack {
                    Label("Model library", systemImage: "square.stack.3d.up")
                        .font(.headline)
                    Spacer()
                    Button {
                        isImportingGGUF = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import GGUF")
                }

                if session.installedModels.isEmpty {
                    Text("No local models installed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.installedModels, id: \.id) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.subheadline.weight(.semibold))
                                Text(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.id == session.activeModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Use") {
                                    Task { await session.selectActiveModel(id: model.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await session.deleteModel(id: model.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    Task { await session.downloadDevModel() }
                } label: {
                    Label(
                        session.isDownloadingDevModel ? "Downloading…" : "Download Small Dev Model",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(session.isDownloadingDevModel)

                if session.isDownloadingDevModel {
                    ProgressView(value: session.devModelDownloadProgress)
                }
            }

            GlassPanel {
                Label("Runtime", systemImage: "bolt.circle")
                    .font(.headline)
                StatusRow(title: "Lifecycle", value: session.state.lifecycle.rawValue)
                StatusRow(title: "Phase", value: session.state.phase.rawValue)
                StatusRow(title: "Provider", value: session.providerID)
                StatusRow(title: "Provider state", value: session.providerLifecycle)
            }

            GlassPanel {
                Label("System", systemImage: "iphone")
                    .font(.headline)
                StatusRow(title: "Target", value: "iPhone 12 Pro Max")
                StatusRow(title: "UI", value: "Native SwiftUI")
                StatusRow(title: "Secrets", value: "Keychain contract")
                Text("Configuration remains contextual; execution stays in the Agent runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $isImportingGGUF,
            allowedContentTypes: [
                UTType(filenameExtension: "gguf") ?? .data,
                .data,
                .item
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                Task {
                    lastImportError = nil
                    await session.importModel(from: selectedURL)
                }
            case .failure(let error):
                lastImportError = error.localizedDescription
            }
        }
    }
}

private struct LifecycleStateBadge: View {
    let state: LocalModelLifecycleState

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch state {
        case .unloaded: return "UNLOADED"
        case .loading(let p): return "LOADING \(Int(p * 100))%"
        case .loaded: return "LOADED"
        case .unloading: return "UNLOADING"
        case .failed: return "FAILED"
        }
    }

    private var color: Color {
        switch state {
        case .unloaded: return .secondary
        case .loading: return .blue
        case .loaded: return .green
        case .unloading: return .orange
        case .failed: return .red
        }
    }
}
