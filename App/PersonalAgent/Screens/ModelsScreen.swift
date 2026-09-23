import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAFoundation

struct ModelsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var showFilePicker = false
    @State private var importError: String?

    var body: some View {
        ScreenScaffold(title: "Models", systemImage: "cpu") {
            MilestoneBanner()

            if let lastError = session.lastError {
                Section {
                    Text("Error: \(lastError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: { showFilePicker = true }) {
                    Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                        .font(.headline)
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data, .data],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        Task {
                            await session.importGGUF(from: url)
                        }
                    case .failure(let error):
                        importError = error.localizedDescription
                    }
                }
            }

            if let importError {
                Text("Import Error: \(importError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Active Model")
                    .font(.headline)

                if let active = session.activeModelDescriptor {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(title: "Name", value: active.name)
                        StatusRow(title: "Architecture", value: active.architecture ?? "Unknown")
                        StatusRow(title: "Context Limit", value: active.contextWindow != nil ? "\(active.contextWindow!)" : "Default (8192)")
                        StatusRow(title: "File Size", value: formattedSize(active.fileSizeBytes))
                        StatusRow(title: "Runtime State", value: lifecycleDescription(session.activeEngineLifecycle))

                        HStack(spacing: 12) {
                            Button("Load") {
                                Task { await session.loadActiveModel() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoadDisabled(session.activeEngineLifecycle))

                            Button("Unload") {
                                Task { await session.unloadActiveModel() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUnloadDisabled(session.activeEngineLifecycle))

                            Button("Deselect") {
                                Task { await session.selectActiveModel(id: nil) }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("No active model selected.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Installed Models (\(session.installedModels.count))")
                    .font(.headline)

                if session.installedModels.isEmpty {
                    Text("No local models installed. Import a GGUF file to begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.installedModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.body.weight(.semibold))
                                Text("\(model.filename) • \(formattedSize(model.fileSizeBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if session.activeModelDescriptor?.id == model.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else {
                                Button("Select") {
                                    Task { await session.selectActiveModel(id: model.id) }
                                }
                                .buttonStyle(.bordered)
                            }

                            Button(role: .destructive) {
                                Task { await session.deleteModel(id: model.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func lifecycleDescription(_ state: LocalModelLifecycleState) -> String {
        switch state {
        case .unloaded: return "Unloaded"
        case .loading(let progress): return "Loading (\(Int(progress * 100))%)"
        case .loaded: return "Loaded"
        case .unloading: return "Unloading"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }

    private func isLoadDisabled(_ state: LocalModelLifecycleState) -> Bool {
        switch state {
        case .loaded, .loading: return true
        default: return false
        }
    }

    private func isUnloadDisabled(_ state: LocalModelLifecycleState) -> Bool {
        switch state {
        case .unloaded, .unloading, .failed: return true
        default: return false
        }
    }
}
