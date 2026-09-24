import SwiftUI
import UniformTypeIdentifiers
import PAFoundation
import PAProviders

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImportingGGUF = false
    @State private var lastImportError: String?

    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gearshape") {
            MilestoneBanner()

            if let error = lastImportError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            // MARK: - Local Models Section (M8.2 / M9.1)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Local Models (GGUF)", systemImage: "cpu")
                        .font(.headline)
                    Spacer()
                    Button {
                        isImportingGGUF = true
                    } label: {
                        Label("Import .gguf", systemImage: "square.and.arrow.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Active Model Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Active Model:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(session.activeModelDescriptor?.name ?? "None Selected")
                            .font(.subheadline.bold())
                        Spacer()
                        LifecycleStateBadge(state: session.activeEngineState)
                    }

                    if let active = session.activeModelDescriptor {
                        HStack(spacing: 12) {
                            if session.activeEngineState == .loaded {
                                Button("Unload Model") {
                                    Task { await session.unloadActiveModel() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            } else {
                                Button("Load Model") {
                                    Task { await session.loadActiveModel() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }

                            Button("Deselect Active") {
                                Task { await session.selectActiveModel(id: nil) }
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                // Installed Models List
                if session.installedModels.isEmpty {
                    Text("No local GGUF models installed. Import a .gguf file to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installed Models (\(session.installedModels.count))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        ForEach(session.installedModels, id: \.id) { model in
                            ModelRow(
                                model: model,
                                isActive: model.id == session.activeModelID,
                                onSelectActive: {
                                    Task { await session.selectActiveModel(id: model.id) }
                                },
                                onDelete: {
                                    Task { await session.deleteModel(id: model.id) }
                                }
                            )
                        }
                    }
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // MARK: - Capabilities Section: Providers
            VStack(alignment: .leading, spacing: 8) {
                Label("Providers", systemImage: "server.rack")
                    .font(.headline)
                StatusRow(title: "Active Provider", value: session.providerID)
                StatusRow(title: "Provider Lifecycle", value: session.providerLifecycle)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // MARK: - Capabilities Section: Skills
            VStack(alignment: .leading, spacing: 8) {
                Label("Skills", systemImage: "puzzlepiece")
                    .font(.headline)
                StatusRow(title: "Registered Modules", value: "\(session.moduleIDs.count)")
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // MARK: - Capabilities Section: Memory
            VStack(alignment: .leading, spacing: 8) {
                Label("Memory", systemImage: "brain")
                    .font(.headline)
                StatusRow(title: "Store Contract", value: "FileBackedMemoryStore (M4)")
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // MARK: - Capabilities Section: Runtime
            VStack(alignment: .leading, spacing: 8) {
                Label("Runtime", systemImage: "cpu")
                    .font(.headline)
                StatusRow(title: "Lifecycle State", value: session.state.lifecycle.rawValue)
                StatusRow(title: "Phase", value: session.state.phase.rawValue)
                StatusRow(title: "Local Engine State", value: lifecycleStateTitle(session.activeEngineState))
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // MARK: - Capabilities Section: Storage & System
            VStack(alignment: .leading, spacing: 8) {
                Label("Storage & System", systemImage: "externaldrive")
                    .font(.headline)
                StatusRow(title: "Secrets", value: "Keychain contract (M0)")
                StatusRow(title: "Target", value: "iPhone 12 Pro Max")
                StatusRow(title: "UI", value: "SwiftUI, local-first")
                Text("API keys will never be stored in SwiftData or UserDefaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .fileImporter(
            isPresented: $isImportingGGUF,
            allowedContentTypes: [.gguf],
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

private extension UTType {
    static var gguf: UTType {
        UTType("org.ggml.gguf") ?? UTType(exportedAs: "org.ggml.gguf", conformingTo: .data)
    }
}

private struct LifecycleStateBadge: View {
    let state: LocalModelLifecycleState

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch state {
        case .unloaded: return "UNLOADED"
        case .loading(let p): return "LOADING (\(Int(p * 100))%)"
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

private struct ModelRow: View {
    let model: LocalModelDescriptor
    let isActive: Bool
    let onSelectActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.name)
                            .font(.subheadline.bold())
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    Text(formattedFileSize(model.fileSizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !isActive {
                        Button("Set Active", action: onSelectActive)
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if model.architecture != nil || model.contextWindow != nil {
                HStack(spacing: 12) {
                    if let arch = model.architecture {
                        Text("Arch: \(arch)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let ctx = model.contextWindow {
                        Text("Context: \(ctx) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private func lifecycleStateTitle(_ state: LocalModelLifecycleState) -> String {
    switch state {
    case .unloaded: return "unloaded"
    case .loading(let p): return "loading (\(Int(p * 100))%)"
    case .loaded: return "loaded"
    case .unloading: return "unloading"
    case .failed(let r): return "failed (\(r))"
    }
}
