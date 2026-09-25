import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAArchitecture

struct ModelsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.activeModelDescriptor?.name ?? "No active model")
                            .font(.headline)
                        Text(activeSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(lifecycleTitle)
                                .font(.caption.bold())
                            Spacer()
                            if session.activeModelDescriptor != nil {
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
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Installed Models") {
                    if session.installedModels.isEmpty {
                        ContentUnavailableView(
                            "No Models",
                            systemImage: "cube.box",
                            description: Text("Import a GGUF model or use Update Models.")
                        )
                    } else {
                        ForEach(session.installedModels, id: \.id) { model in
                            Button {
                                Task { await session.selectActiveModel(id: model.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.name)
                                            .foregroundStyle(.primary)
                                        Text(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.id == session.activeModelID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
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

                Section {
                    ModelCatalogContent(session: session)
                } header: {
                    Text("Model Catalog")
                }

                if let errorMessage {
                    Section("Import Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let sessionError = session.lastError {
                    Section("Model Error") {
                        Text(sessionError)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassScreenBackground())
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import GGUF")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.pathExtension.lowercased() == "gguf" else {
                    errorMessage = "Please select a .gguf model file."
                    return
                }
                errorMessage = nil
                Task { await session.importModel(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var activeSubtitle: String {
        switch session.activeEngineState {
        case .unloaded: return "Selected · ready to load"
        case .loading: return "Loading local model…"
        case .loaded: return "Loaded · ready for local inference"
        case .unloading: return "Unloading local model…"
        case .failed(let reason): return "Failed · \(reason)"
        }
    }

    private var lifecycleTitle: String {
        switch session.activeEngineState {
        case .unloaded: return "UNLOADED"
        case .loading(let progress): return "LOADING \(Int(progress * 100))%"
        case .loaded: return "LOADED"
        case .unloading: return "UNLOADING"
        case .failed: return "FAILED"
        }
    }
}


private struct ModelCatalogContent: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await session.updateModelCatalog() }
            } label: {
                Label(
                    session.isUpdatingModelCatalog ? "Updating…" : "Update Models",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(session.isUpdatingModelCatalog || session.isDownloadingModelPack)

            if !session.remoteModels.isEmpty {
                Button {
                    Task { await session.downloadTestPack() }
                } label: {
                    Label(
                        session.isDownloadingModelPack ? "Downloading Test Pack…" : "Download Test Pack",
                        systemImage: "shippingbox"
                    )
                }
                .disabled(session.isDownloadingModelPack)

                ForEach(session.remoteModels, id: \.id) { model in
                    Button {
                        Task { await session.downloadModel(model) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.name)
                                Text("\(model.parameterCount) · \(model.quantization) · \(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: session.installedModels.contains(where: { $0.filename == model.filename }) ? "checkmark.circle" : "arrow.down.circle")
                                .foregroundStyle(session.installedModels.contains(where: { $0.filename == model.filename }) ? .secondary : .tint)
                        }
                    }
                    .disabled(session.isDownloadingModelPack)
                }
            }

            if let updated = session.modelCatalogUpdatedAt {
                Text("Updated \\(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if session.isDownloadingModelPack {
                ProgressView(value: session.modelDownloadProgress)
            }
        }
    }
}
