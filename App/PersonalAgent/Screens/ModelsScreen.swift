import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAComposition

struct ModelsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        ScreenScaffold(title: "Models", systemImage: "cube.box") {
            GlassPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active model").font(.headline)
                        Text(session.activeModelDescriptor?.name ?? "None selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            if session.activeEngineState == .loaded {
                                await session.unloadActiveModel()
                            } else {
                                await session.loadActiveModel()
                            }
                        }
                    } label: {
                        Text(session.activeEngineState == .loaded ? "Unload" : "Load")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.activeModelDescriptor == nil)
                }
                StatusRow(title: "State", value: lifecycleTitle)
            }

            GlassPanel {
                HStack {
                    Label("Installed models", systemImage: "square.stack.3d.up")
                        .font(.headline)
                    Spacer()
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import GGUF")
                }

                if session.installedModels.isEmpty {
                    Text("No GGUF models installed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.installedModels, id: \.id) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
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
            }

            GlassPanel {
                Label("Development", systemImage: "arrow.down.circle")
                    .font(.headline)
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

            if let errorMessage {
                GlassPanel {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.gguf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                errorMessage = nil
                Task {
                    let securityScoped = url.startAccessingSecurityScopedResource()
                    defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
                    await session.importModel(from: url)
                    errorMessage = session.lastError
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var lifecycleTitle: String {
        switch session.activeEngineState {
        case .unloaded: return "UNLOADED"
        case .loading(let progress): return "LOADING \(Int(progress * 100))%"
        case .loaded: return "LOADED"
        case .unloading: return "UNLOADING"
        case .failed(let reason): return "FAILED · \(reason)"
        }
    }
}

private extension UTType {
    static let gguf = UTType(importedAs: "org.ggml.gguf", conformingTo: .data)
}
