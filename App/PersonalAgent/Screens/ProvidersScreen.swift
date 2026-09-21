import SwiftUI
import UniformTypeIdentifiers
import PAArchitecture
import PAFoundation
import PAProviders

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession

    @State private var isImporterPresented = false
    @State private var testPrompt = "Hello, write a short greeting."
    @State private var generationOutput = ""
    @State private var isGenerating = false
    @State private var activeGenerationTask: Task<Void, Never>? = nil

    var body: some View {
        ScreenScaffold(title: "Providers & Local Models", systemImage: "server.rack") {
            MilestoneBanner()

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider Status")
                    .font(.headline)
                StatusRow(title: "Selected Provider", value: session.providerID)
                StatusRow(title: "Lifecycle", value: session.providerLifecycle)
            }
            .padding(.vertical, 4)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Local GGUF Models")
                        .font(.headline)
                    Spacer()
                    Button(action: { isImporterPresented = true }) {
                        Label("Import GGUF", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if session.localModels.isEmpty {
                    Text("No local GGUF models imported yet. Tap 'Import GGUF' to select a .gguf model file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(session.localModels) { desc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(desc.name)
                                    .font(.body)
                                    .bold()
                                Text("\(desc.filename) • \(formatBytes(desc.fileSizeBytes)) • Arch: \(desc.architecture ?? "GGUF v\(desc.formatVersion)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.activeModelDescriptor?.id == desc.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Select") {
                                    Task {
                                        try? await session.selectActiveLocalModel(id: desc.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            Button(role: .destructive) {
                                Task {
                                    try? await session.deleteLocalModel(id: desc.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Local Model Test Prompt")
                    .font(.headline)

                TextField("Enter prompt...", text: $testPrompt)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(action: runInference) {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                Text("Generating...")
                            }
                        } else {
                            Label("Run Local Model", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || session.activeModelDescriptor == nil)

                    if isGenerating {
                        Button("Cancel") {
                            activeGenerationTask?.cancel()
                            isGenerating = false
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !generationOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generated Output:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(generationOutput)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        do {
                            try await session.importGGUFModel(from: url)
                        } catch {
                            session.lastError = "Import failed: \(error.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                session.lastError = "File picker error: \(error.localizedDescription)"
            }
        }
    }

    private func runInference() {
        isGenerating = true
        generationOutput = ""

        activeGenerationTask = Task {
            do {
                guard let activeEngine = try await session.activeLocalModelEngine() else {
                    session.lastError = "No active local model engine configured"
                    isGenerating = false
                    return
                }

                let options = LocalModelLoadingOptions()
                try await activeEngine.load(options: options)

                let genReq = LocalModelGenerationRequest(prompt: testPrompt)
                let stream = activeEngine.generateStream(request: genReq)

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    generationOutput += chunk.textDelta
                }

                try await activeEngine.unload()
            } catch {
                if !Task.isCancelled {
                    session.lastError = "Inference failed: \(error.localizedDescription)"
                }
            }
            isGenerating = false
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
