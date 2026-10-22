import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAComposition

struct ModelsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImporting = false
    @State private var modelSearch = ""
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
                    .disabled(session.activeModelDescriptor == nil || isTransitioning)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("State").foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    lifecycleValue.fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.vertical, 3)
                if isTransitioning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Model transition in progress")
                }
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
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search installed models…", text: $modelSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !modelSearch.isEmpty {
                            Button {
                                modelSearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Clear model search")
                        }
                    }
                    .padding(10)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Text("\(filteredInstalledModels.count) of \(session.installedModels.count) models")
                        .font(.caption).foregroundStyle(.secondary)
                    if filteredInstalledModels.isEmpty {
                        ContentUnavailableView(
                            "No matching models",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different model name.")
                        )
                    } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredInstalledModels, id: \.id) { model in
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
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Downloading and verifying model…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassPanel {
                Label("Chọn model theo công việc", systemImage: "slider.horizontal.3")
                    .font(.headline)
                modelGuide("Model local nhỏ", "Phù hợp thử nghiệm, tác vụ ngắn và chế độ ngoại tuyến; chất lượng phụ thuộc model, lượng tử hóa và context.", symbol: "iphone")
                modelGuide("Model local lớn hơn", "Có thể xử lý tốt hơn nhưng tăng RAM, thời gian nạp, nhiệt và nguy cơ hệ thống kết thúc tiến trình.", symbol: "memorychip")
                modelGuide("Model qua provider", "Có thể mạnh hơn với tác vụ khó nhưng cần mạng, credential và kiểm soát dữ liệu gửi ra ngoài.", symbol: "cloud")
                modelGuide("Code Engine", "Ưu tiên cho phép tính, validation, parsing và quy tắc cần kết quả xác định.", symbol: "curlybraces")
                Text("Không chọn model chỉ theo số tham số. Đo chất lượng trên tác vụ thật cùng độ trễ, tốc độ token, mức tiêu thụ năng lượng và độ ổn định.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Vòng đời model local", systemImage: "arrow.trianglehead.2.clockwise")
                    .font(.headline)
                modelStep("01", "Import", "Chọn GGUF từ Files; không đưa model lớn hoặc bí mật vào Git.")
                modelStep("02", "Validate", "Kiểm tra định dạng và metadata trước khi tin tệp.")
                modelStep("03", "Load", "Nạp engine và quan sát trạng thái; model có thể chưa phù hợp giới hạn thiết bị.")
                modelStep("04", "Generate", "Thử prompt ngắn, streaming và cancellation trước tác vụ dài.")
                modelStep("05", "Unload", "Giải phóng model khi không cần và theo dõi bộ nhớ/nhiệt.")
                Text("Trạng thái LOADED chỉ xác nhận engine đã nạp; không chứng minh model trả lời chính xác hay chạy ổn định trong thời gian dài.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let visibleError = errorMessage ?? session.lastError {
                GlassPanel {
                    Label("Model operation failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(visibleError)
                        .font(.footnote)
                        .textSelection(.enabled)
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


    private func modelGuide(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.monospaced().bold()).foregroundStyle(.tint).frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filteredInstalledModels: [LocalModelDescriptor] {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.installedModels }
        return session.installedModels.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isTransitioning: Bool {
        switch session.activeEngineState {
        case .loading, .unloading:
            return true
        case .unloaded, .loaded, .failed:
            return false
        }
    }

    @ViewBuilder
    private var lifecycleValue: some View {
        switch session.activeEngineState {
        case .unloaded:
            Text("UNLOADED")
        case .loading(let progress):
            HStack(spacing: 2) {
                Text("LOADING")
                Text(verbatim: "\(Int(progress * 100))%")
            }
        case .loaded:
            Text("LOADED")
        case .unloading:
            Text("UNLOADING")
        case .failed(let reason):
            HStack(spacing: 0) {
                Text("FAILED")
                Text(verbatim: " · \(reason)")
            }
        }
    }
}

private extension UTType {
    static let gguf = UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data
}
