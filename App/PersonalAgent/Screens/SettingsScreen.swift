import SwiftUI
import UniformTypeIdentifiers
import PAKernel
import PAProviders
import PAProvidersRemote
import PAComposition
import PASecurity
import PAImportGateway
import PAWorkspace
import UIKit

private enum SettingsFileImportKind {
    case gguf
    case general
}

private struct OpenRouterModelOption: Identifiable {
    let id: String
    let name: String

    var title: String { name == id ? id : "\(name) · \(id)" }
}

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImportingFile = false
    @State private var fileImportKind: SettingsFileImportKind = .general
    @State private var importedFiles: [ImportedFile] = []
    @State private var importPreview: ImportedFilePreview?
    @State private var githubTokenDraft = ""
    @State private var isGitHubSyncing = false
    @State private var githubSyncStatus = "Not configured"
    @AppStorage("github.sync.owner") private var githubSyncOwner = ""
    @AppStorage("github.sync.repository") private var githubSyncRepository = ""
    @AppStorage("github.sync.branch") private var githubSyncBranch = "main"
    @State private var lastImportError: String?
    @State private var lastImportStatus: String?
    @AppStorage("app.language") private var appLanguage = "vi"
    @AppStorage("ui.v2.enabled") private var uiV2Enabled = false
    @State private var updateState: UpdateState = .idle
    @State private var copiedUpdateLink = false
    @AppStorage("provider.execution.mode") private var executionMode = UserDefaults.standard.bool(forKey: "provider.remote.enabled") ? "remote" : "local"
    @State private var remoteProvider = UserDefaults.standard.string(forKey: "provider.remote.id") ?? "openai"
    @State private var compatibleEndpoint = UserDefaults.standard.string(forKey: "provider.compatible.endpoint") ?? ""
    @State private var compatibleModel = UserDefaults.standard.string(forKey: "provider.compatible.model") ?? "openrouter/free"
    @State private var openRouterModels: [OpenRouterModelOption] = []
    @State private var isRefreshingOpenRouterModels = false
    @State private var openRouterModelsMessage: String?
    @State private var apiKey = ""
    @State private var credentialState: CredentialState = .unknown
    @State private var connectionState: ConnectionState = .idle
    @AppStorage("chat.context.turns") private var contextTurns = 12
    @AppStorage("privacy.persistChat") private var persistChat = true
    @AppStorage("permissions.capability.read") private var allowCapabilityRead = true
    @AppStorage("permissions.capability.write") private var allowCapabilityWrite = false
    @AppStorage("permissions.capability.execute") private var allowCapabilityExecute = false
    @AppStorage("permissions.capability.network") private var allowCapabilityNetwork = false

    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gearshape") {
            GlassPanel {
                Label("Giao diện", systemImage: "paintbrush.pointed")
                    .font(.headline)
                Toggle("UI V2 · giao diện nhắn tin", isOn: $uiV2Enabled)
                Text("Bật để dùng giao diện Messages, Tasks, Profile và Settings. Có thể tắt bất cứ lúc nào để quay lại giao diện hiện tại.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = lastImportError ?? session.lastError {
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
                Label("Quyền thực thi của Agent", systemImage: "checkmark.shield")
                    .font(.headline)
                Text("Các quyền này được kiểm tra lại trong Runtime mỗi lần chạy Skill; tắt quyền sẽ chặn lần thực thi tiếp theo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Đọc dữ liệu", isOn: $allowCapabilityRead)
                Toggle("Ghi dữ liệu", isOn: $allowCapabilityWrite)
                Toggle("Chạy Skills / Modules", isOn: $allowCapabilityExecute)
                Toggle("Truy cập mạng", isOn: $allowCapabilityNetwork)
                Label("Thao tác phá huỷ luôn cần bước phê duyệt riêng.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        fileImportKind = .gguf
                        isImportingFile = true
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
                    LazyVStack(alignment: .leading, spacing: 12) {
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
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Downloading and verifying model…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }



            GlassPanel {
                Label("AgentOS Storage", systemImage: "externaldrive")
                    .font(.headline)
                Text("Browse and search the safe, human-readable workspace; edit Markdown/text with read-back verification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    AgentOSStorageBrowserScreen()
                } label: {
                    Label("Open Storage Browser", systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            GlassPanel {
                Label("Local AgentOS storage", systemImage: "folder")
                    .font(.headline)
                Text("AgentOS data is stored in the app's Documents/AgentOS folder. Open Files → On My iPhone → Personal Agent → AgentOS to view and manage local files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Agents, Skills, memory and runtime state stay on this iPhone. API keys remain in Keychain; local model binaries remain in managed model storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("GitHub repository sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Text("Syncs text/source files with a GitHub branch. Divergent edits stop as conflicts. Memory, logs, cache, credentials and model binaries are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Repository owner", text: $githubSyncOwner)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Repository name", text: $githubSyncRepository)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Branch", text: $githubSyncBranch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("GitHub token (stored in Keychain)", text: $githubTokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save token securely") { saveGitHubSyncToken() }
                        .buttonStyle(.bordered)
                        .disabled(githubTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete token", role: .destructive) { deleteGitHubSyncToken() }
                        .buttonStyle(.bordered)
                }
                HStack {
                    Button {
                        Task { await syncGitHubRepository(preview: true) }
                    } label: {
                        Label("Preview changes", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGitHubSyncing)

                    Button {
                        Task { await syncGitHubRepository() }
                    } label: {
                        if isGitHubSyncing {
                            ProgressView()
                        } else {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGitHubSyncing)
                }
                Text(githubSyncStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            AgentOSUpdateSettingsSection(session: session)

            GlassPanel {
                HStack {
                    Label("Imported files", systemImage: "doc.on.doc")
                        .font(.headline)
                    Spacer()
                    Button {
                        fileImportKind = .general
                        isImportingFile = true
                    } label: {
                        Label("Import files", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Files are stored locally. Content is processed only when a matching format reader is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let status = lastImportStatus {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }

                if importedFiles.isEmpty {
                    Text("No imported files yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(importedFiles) { file in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.originalName)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Stored · readable formats can be previewed")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Button {
                                    Task { await previewImportedFile(file) }
                                } label: {
                                    Label("Read", systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) {
                                    Task { await removeImportedFile(file.id) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete \(file.originalName)")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .task { await refreshImportedFiles() }
            .sheet(item: $importPreview) { preview in
                NavigationStack {
                    ScrollView {
                        Text(preview.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(preview.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { importPreview = nil }
                        }
                    }
                }
            }
            GlassPanel {
                Label("Remote Provider", systemImage: "server.rack")
                    .font(.headline)

                Picker("Inference", selection: $executionMode) {
                    Text("Local").tag("local")
                    Text("Remote").tag("remote")
                }
                .pickerStyle(.segmented)
                .onChange(of: executionMode) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "provider.execution.mode")
                    if newValue == "remote" {
                        UserDefaults.standard.set(true, forKey: "provider.remote.enabled")
                    }
                    Task { await session.refresh() }
                }

                if executionMode == "remote" {
                    Picker("Provider", selection: $remoteProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Grok").tag("grok")
                        Text("OpenAI Compatible").tag("openai-compatible")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: remoteProvider) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "provider.remote.id")
                        apiKey = ""
                        credentialState = loadCredentialState(for: newValue)
                        connectionState = .idle
                        clearProviderConnectionTest()
                    }

                    if remoteProvider == "openai-compatible" {
                        HStack {
                            Button("Use OpenRouter") {
                                compatibleEndpoint = "https://openrouter.ai/api/v1/chat/completions"
                                compatibleModel = "openrouter/free"
                                UserDefaults.standard.set(compatibleEndpoint, forKey: "provider.compatible.endpoint")
                                UserDefaults.standard.set(compatibleModel, forKey: "provider.compatible.model")
                                openRouterModelsMessage = nil
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button {
                                Task { await refreshOpenRouterModels() }
                            } label: {
                                if isRefreshingOpenRouterModels { ProgressView() }
                                else { Label("Refresh models", systemImage: "arrow.clockwise") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingOpenRouterModels || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && credentialState != .saved))
                        }
                        TextField("Chat completions endpoint", text: $compatibleEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: compatibleEndpoint) { _, _ in clearProviderConnectionTest() }
                            .keyboardType(.URL)
                        if compatibleEndpoint.localizedCaseInsensitiveContains("openrouter.ai") && !openRouterModels.isEmpty {
                            Picker("Model", selection: $compatibleModel) {
                                ForEach(openRouterModels) { model in
                                    Text(model.title).tag(model.id)
                                }
                            }
                            .onChange(of: compatibleModel) { _, value in
                                UserDefaults.standard.set(value, forKey: "provider.compatible.model")
                            }
                            Text("Selected model ID: \(compatibleModel)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Model ID", text: $compatibleModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if let openRouterModelsMessage {
                            Text(openRouterModelsMessage)
                                .font(.caption)
                                .foregroundStyle(openRouterModelsMessage.hasPrefix("Loaded") ? .green : .secondary)
                        }
                    }

                    SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)

                HStack(spacing: 8) {
                    Button("Save") { saveProviderCredential() }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && credentialState != .saved)
                            || (remoteProvider == "openai-compatible" && compatibleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || (remoteProvider == "openai-compatible" && compatibleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        )
                    Button("Test connection") {
                        Task { await testProviderConnection() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        connectionState == .testing ||
                        (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && credentialState != .saved) ||
                        (remoteProvider == "openai-compatible" && compatibleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                        (remoteProvider == "openai-compatible" && compatibleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                    Button("Delete", role: .destructive) { deleteProviderCredential() }
                        .buttonStyle(.bordered)
                }

                switch credentialState {
                case .unknown:
                    Text("Enter an API key to configure remote inference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .saved:
                    Text("API key saved securely in Keychain.")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .missing:
                    Text("No API key saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if case .success = connectionState {
                    Text("Connection successful.")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if case .failure(let message) = connectionState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if connectionState == .testing {
                    ProgressView("Testing connection…")
                        .font(.caption)
                }
            }

            GlassPanel {
                Label("Conversation context", systemImage: "text.alignleft")
                    .font(.headline)
                Picker("Context turns", selection: $contextTurns) {
                    ForEach([4, 8, 12, 24, 48], id: \.self) { limit in
                        Text("\(limit) turns").tag(limit)
                    }
                }
                .onChange(of: contextTurns) { _, limit in
                    session.setChatContextTurnLimit(limit)
                }
                Text("Controls how many recent turns are sent into the next model request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Privacy", systemImage: "lock.shield")
                    .font(.headline)
                Toggle("Persist chat history", isOn: $persistChat)
                    .onChange(of: persistChat) { _, enabled in
                        session.setChatPersistence(enabled)
                    }
                Text(persistChat
                     ? "Conversations are stored locally on this device."
                     : "Chat history is kept only for the current session and local history is cleared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Language", systemImage: "globe")
                    .font(.headline)

                Picker("Language", selection: $appLanguage) {
                    Text("English").tag("en")
                    Text("Tiếng Việt").tag("vi")
                }
                .pickerStyle(.segmented)
            }

            GlassPanel {
                HStack {
                    Label("App update", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await checkForUpdate() }
                } label: {
                    Label(updateState.buttonTitleKey, systemImage: updateState.isChecking ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateState.isChecking)

                if case .available(let version, let url) = updateState {
                    HStack(spacing: 5) {
                        Text("New version available")
                            .font(.subheadline.weight(.semibold))
                        Text(version)
                            .font(.subheadline.weight(.semibold))
                    }
                    Button(copiedUpdateLink ? "Copied" : "Copy update link") {
                        UIPasteboard.general.string = url.absoluteString
                        copiedUpdateLink = true
                    }
                    .buttonStyle(.bordered)
                } else if case .current = updateState {
                    Text("You are using the latest version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .failed = updateState {
                    Text("Could not check for updates right now.")
                        .font(.caption)
                        .foregroundStyle(.red)
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
        .environment(\.locale, Locale(identifier: appLanguage))
        .task {
            credentialState = loadCredentialState(for: remoteProvider)
            compatibleEndpoint = UserDefaults.standard.string(forKey: "provider.compatible.endpoint") ?? compatibleEndpoint
            compatibleModel = UserDefaults.standard.string(forKey: "provider.compatible.model") ?? compatibleModel
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: fileImportKind == .gguf
                ? [UTType(filenameExtension: "gguf") ?? .data]
                : [.item],
            allowsMultipleSelection: fileImportKind == .general
        ) { result in
            switch result {
            case .success(let urls):
                switch fileImportKind {
                case .gguf:
                    guard let selectedURL = urls.first else { return }
                    guard selectedURL.pathExtension.lowercased() == "gguf" else {
                        lastImportError = "Chỉ hỗ trợ tệp GGUF."
                        return
                    }
                    Task {
                        lastImportError = nil
                        await session.importModel(from: selectedURL)
                        lastImportError = session.lastError
                    }
                case .general:
                    Task { await importFiles(urls) }
                }
            case .failure(let error):
                lastImportError = error.localizedDescription
            }
        }
    }
}

}

private struct LifecycleStateBadge: View {
    let state: LocalModelLifecycleState

    var body: some View {
        Text(LocalizedStringKey(title))
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


private enum UpdateState {
    case idle
    case checking
    case current
    case available(String, URL)
    case failed

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var buttonTitleKey: LocalizedStringKey {
        isChecking ? "Checking…" : "Check for updates"
    }
}

private struct ReleaseAsset: Decodable {
    let name: String
    let browser_download_url: URL
}

private struct LatestRelease: Decodable {
    let tag_name: String
    let html_url: URL
    let name: String
    let assets: [ReleaseAsset]
    let prerelease: Bool
    let created_at: String

    var preReleaseCode: String? {
        let source = "\(tag_name) \(name)"
        let pattern = #"(?i)dev-pr-\d+-([0-9a-f]{12})(?:\s|$)"#
        guard let match = source.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(source[match]).split(separator: "-").last.map(String.init)
    }
}

private extension SettingsScreen {
    func checkForUpdate() async {
        updateState = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/hgblue09124-code/PersonalAgent-iOS/releases?per_page=100")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let releases = try JSONDecoder().decode([LatestRelease].self, from: data)
            let currentPreReleaseCode = Bundle.main.object(forInfoDictionaryKey: "PA_PRE_RELEASE_CODE") as? String
            let currentChannel = Bundle.main.object(forInfoDictionaryKey: "PA_PRE_RELEASE_CHANNEL") as? String
            let taggedPattern = #"^v\d+\.\d+\.\d+-(alpha|beta|rc)(\.\d+)?$"#
            let isTaggedPrerelease = currentChannel?.range(of: taggedPattern, options: .regularExpression) != nil
            let channelFamily = currentChannel?.replacingOccurrences(
                of: #"(\.\d+)$"#,
                with: "",
                options: .regularExpression
            )
            let candidates = releases
                .filter(\.prerelease)
                .filter { release in
                    guard let channel = currentChannel, !channel.isEmpty else { return true }
                    if isTaggedPrerelease, let family = channelFamily {
                        return release.tag_name == family || release.tag_name.hasPrefix("\(family).")
                    }
                    return release.tag_name == channel
                }
                .compactMap { release -> (LatestRelease, String)? in
                    let identity = release.preReleaseCode ?? release.tag_name
                    return (release, identity)
                }
                .sorted(by: { $0.0.created_at > $1.0.created_at })

            guard let (release, releaseIdentity) = candidates.first else {
                updateState = .current
                return
            }

            let currentIdentity = isTaggedPrerelease ? currentChannel : currentPreReleaseCode
            guard currentIdentity != releaseIdentity else {
                updateState = .current
                return
            }

            let downloadURL = release.assets.first(where: { $0.name == "PersonalAgent-unsigned.ipa" })?.browser_download_url
                ?? release.html_url
            copiedUpdateLink = false
            updateState = .available(releaseIdentity, downloadURL)
        } catch {
            updateState = .failed
        }
    }
}

private extension SettingsScreen {
    var importedFilesDirectoryURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "PersonalAgent/ImportedFiles", directoryHint: .isDirectory)
    }

    func saveGitHubSyncToken() {
        let token = githubTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try KeychainSecretStore().store(account: "github.repository.token", secret: Data(token.utf8))
            githubTokenDraft = ""
            githubSyncStatus = "GitHub token saved in Keychain."
        } catch {
            githubSyncStatus = "Could not save the GitHub token securely."
        }
    }

    func deleteGitHubSyncToken() {
        do {
            try KeychainSecretStore().delete(account: "github.repository.token")
            githubTokenDraft = ""
            githubSyncStatus = "GitHub token removed."
        } catch {
            githubSyncStatus = "Could not remove the GitHub token."
        }
    }

    func syncGitHubRepository(preview: Bool = false) async {
        isGitHubSyncing = true
        defer { isGitHubSyncing = false }
        let result = await session.syncGitHubWorkspace(preview: preview)
        githubSyncStatus = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func previewImportedFile(_ file: ImportedFile) async {
        do {
            let store = try ImportedFileStore(directoryURL: importedFilesDirectoryURL)
            let content = try await ImportedFileContentReader().read(file, from: store)
            let previewText: String
            if let rows = content.csvRows {
                previewText = "CSV/TSV · \(rows.count) rows\n\n" + content.text
            } else {
                previewText = content.text
            }
            importPreview = ImportedFilePreview(id: file.id, title: file.originalName, text: previewText)
            lastImportError = nil
        } catch {
            lastImportError = "Could not read \(file.originalName): \(error)"
        }
    }

    func refreshImportedFiles() async {
        do {
            let store = try ImportedFileStore(directoryURL: importedFilesDirectoryURL)
            importedFiles = await store.listImports()
        } catch {
            lastImportError = String(localized: "Could not open imported-file library: \(error.localizedDescription)")
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            lastImportStatus = nil
            lastImportError = "No files were selected."
            return
        }
        lastImportStatus = nil
        lastImportError = nil
        do {
            let store = try ImportedFileStore(directoryURL: importedFilesDirectoryURL)
            var failures: [String] = []
            var importedCount = 0
            for url in urls {
                do {
                    let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
                    _ = try await store.importFile(from: url, contentTypeIdentifier: typeIdentifier)
                    importedCount += 1
                } catch {
                    failures.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
            importedFiles = await store.listImports()
            if failures.isEmpty {
                lastImportStatus = "Imported and saved " + String(importedCount) + " file(s) locally."
                lastImportError = nil
            } else {
                lastImportError = "Imported " + String(importedCount) + " file(s); failed: " + failures.joined(separator: "; ")
            }
        } catch {
            lastImportError = "Could not open imported-file library: " + error.localizedDescription
        }
    }

    func removeImportedFile(_ id: UUID) async {
        do {
            let store = try ImportedFileStore(directoryURL: importedFilesDirectoryURL)
            try await store.removeImport(id: id)
            importedFiles = await store.listImports()
            lastImportError = nil
        } catch {
            lastImportError = String(localized: "Could not delete imported file: \(error.localizedDescription)")
        }
    }
}


private struct AgentOSUpdateSettingsSection: View {
    @ObservedObject var session: KernelSession
    @AppStorage("github.sync.owner") private var owner = ""
    @AppStorage("github.sync.repository") private var repository = ""
    @AppStorage("github.sync.branch") private var branch = "main"
    @State private var busy = false
    @State private var isStaging = false
    @State private var stagingTask: Task<Void, Never>?
    @State private var status = "Chưa kiểm tra."
    private struct StagedUpdate { let manifest: AgentOSSoftUpdateManifest; let url: URL }
    @State private var staged: StagedUpdate?
    @State private var rollbackDirectory: URL?
    @State private var activeManifest: AgentOSSoftUpdateManifest?

    var body: some View {
        GlassPanel {
            Label("AgentOS Soft Update", systemImage: "arrow.down.circle").font(.headline)
            Text("Đang cài: \(UserDefaults.standard.string(forKey: "agentos.update.revision") ?? "initial")").font(.caption.monospaced())
            Text("Cập nhật Agent/Skill/Module dạng văn bản; không tải hay chạy mã Swift.")
                .font(.caption).foregroundStyle(.secondary)
            Text(status).font(.footnote).textSelection(.enabled)
            Button {
                stagingTask = Task { await stageUpdate() }
            } label: {
                if busy { ProgressView() } else { Label("Kiểm tra & tải vào vùng tạm", systemImage: "arrow.down.to.line") }
            }
            .buttonStyle(.borderedProminent).disabled(busy)
            if isStaging {
                Button("Hủy tải") { stagingTask?.cancel(); status = "Đang hủy tải an toàn..." }
                    .buttonStyle(.bordered).disabled(!isStaging)
            }
            if staged != nil {
                Button("Xác thực lại, sao lưu và kích hoạt") { Task { await activate() } }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if activeManifest != nil {
                Button("Khôi phục các tệp đã cập nhật", role: .destructive) { Task { await rollback() } }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
        .task { await loadRollbackState() }
    }

    private func stageUpdate() async {
        busy = true
        isStaging = true
        defer { busy = false; isStaging = false; stagingTask = nil }
        staged = nil
        status = "Đang kiểm tra manifest và tải tệp an toàn..."
        do {
            guard !owner.isEmpty, !repository.isEmpty, !branch.isEmpty else {
                status = "Cấu hình GitHub repository trong phần GitHub sync trước."
                return
            }
            guard let tokenData = try KeychainSecretStore().load(account: "github.repository.token"),
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = "Hãy lưu GitHub token trong Keychain trước."
                return
            }
            let location = try GitHubRepositoryLocation(owner: owner, repository: repository, branch: branch)
            let workspace = try LocalAgentWorkspace.documents()
            try await workspace.prepare()
            let workspaceRoot = await workspace.rootURL
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let root = support.appendingPathComponent("PersonalAgent/AgentOSUpdateStaging", isDirectory: true)
            let current = UserDefaults.standard.string(forKey: "agentos.update.revision") ?? "initial"
            let client = try AgentOSSoftUpdateClient(location: location, tokenProvider: { token })
            let result = try await client.stageUpdate(currentRevision: current, runtimeCompatibility: "runtime-v1",
                workspaceURL: workspaceRoot, stagingRootURL: root, progress: { completed, total in
                    await MainActor.run { status = "Đang tải/xác minh tệp \(completed)/\(total)..." }
                })
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: result.stagingURL)
                status = "Đã hủy tải; workspace chưa thay đổi."
                return
            }
            staged = StagedUpdate(manifest: result.manifest, url: result.stagingURL)
            status = "Đã tải và xác minh \(result.manifest.files.count) tệp; workspace chưa thay đổi."
        } catch is CancellationError {
            status = "Đã hủy tải; workspace chưa thay đổi."
        } catch let error as URLError where error.code == .cancelled {
            status = "Đã hủy tải; workspace chưa thay đổi."
        } catch AgentOSSoftUpdateError.alreadyCurrent {
            status = "Đang sử dụng bản AgentOS mới nhất."
        } catch {
            status = "Không thể tải bản cập nhật: \(error.localizedDescription)"
        }
    }

    private func activate() async {
        guard let staged else { return }
        busy = true
        defer { busy = false }
        do {
            let workspace = try LocalAgentWorkspace.documents()
            try await workspace.prepare()
            let workspaceRoot = await workspace.rootURL
            var files: [(String, String)] = []
            var originals: [(path: String, data: Data?)] = []
            for item in staged.manifest.files {
                guard let baseHash = item.baseSHA256,
                      AgentOSSoftUpdateClient.isAllowedPath(item.path) else {
                    throw AgentOSSoftUpdateError.invalidManifest
                }
                let target = workspaceRoot.appendingPathComponent(item.path).standardizedFileURL
                guard target.path.hasPrefix(workspaceRoot.standardizedFileURL.path + "/") else {
                    throw AgentOSSoftUpdateError.unsafePath(item.path)
                }
                let actualBase: String
                if FileManager.default.fileExists(atPath: target.path) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
                    guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                        throw AgentOSSoftUpdateError.unsafePath(item.path)
                    }
                    let originalData = try Data(contentsOf: target)
                    originals.append((item.path, originalData))
                    actualBase = AgentOSSoftUpdateClient.sha256Hex(originalData)
                } else {
                    originals.append((item.path, nil))
                    actualBase = "missing"
                }
                guard actualBase.caseInsensitiveCompare(baseHash) == .orderedSame else {
                    throw AgentOSSoftUpdateError.localConflict(item.path)
                }
                let stagedFile = staged.url.appendingPathComponent(item.path).standardizedFileURL
                guard stagedFile.path.hasPrefix(staged.url.standardizedFileURL.path + "/") else {
                    throw AgentOSSoftUpdateError.unsafePath(item.path)
                }
                let data = try Data(contentsOf: stagedFile)
                guard Int64(data.count) == item.byteCount,
                      AgentOSSoftUpdateClient.sha256Hex(data).caseInsensitiveCompare(item.sha256) == .orderedSame,
                      let text = String(data: data, encoding: .utf8),
                      !WorkspaceContentSafety.containsPotentialSecret(text) else {
                    throw AgentOSSoftUpdateError.hashMismatch(item.path)
                }
                files.append((item.path, text))
            }
            try validateDefinitionPayloads(files, workspaceRoot: workspaceRoot)
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let snapshots = try DurableWorkspaceSnapshotStore(directoryURL: support.appendingPathComponent("PersonalAgent/AgentOSSnapshots", isDirectory: true))
            let snapshot = try await snapshots.createSnapshot(of: workspaceRoot)
            let rollbackRoot = support.appendingPathComponent("PersonalAgent/AgentOSUpdateRollback/\(UUID().uuidString.lowercased())", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
                for original in originals {
                    guard let data = original.data else { continue }
                    let backup = rollbackRoot.appendingPathComponent(original.path).standardizedFileURL
                    guard backup.path.hasPrefix(rollbackRoot.standardizedFileURL.path + "/") else { throw AgentOSSoftUpdateError.unsafePath(original.path) }
                    try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: backup, options: .atomic)
                }
                let record = AgentOSRollbackRecord(manifest: staged.manifest, missingPaths: originals.filter { $0.data == nil }.map { $0.path })
                try JSONEncoder().encode(record).write(to: rollbackRoot.appendingPathComponent("rollback.json"), options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: rollbackRoot)
                throw error
            }
            do {
                for (path, text) in files { try await workspace.writeFile(text, to: path) }
            } catch {
                try await snapshots.restore(snapshotID: snapshot.id, to: workspaceRoot)
                try? FileManager.default.removeItem(at: rollbackRoot)
                throw error
            }
            self.rollbackDirectory = rollbackRoot
            activeManifest = staged.manifest
            UserDefaults.standard.set(rollbackRoot.path, forKey: "agentos.update.rollback.path")
            UserDefaults.standard.set(staged.manifest.revision, forKey: "agentos.update.revision")
            await session.refresh()
            try? FileManager.default.removeItem(at: staged.url)
            self.staged = nil
            status = "Đã kích hoạt revision \(staged.manifest.revision); có thể khôi phục bản trước."
        } catch {
            status = "Kích hoạt bị chặn/đã rollback: \(error.localizedDescription)"
        }
    }

    private func loadRollbackState() async {
        guard activeManifest == nil,
              let savedPath = UserDefaults.standard.string(forKey: "agentos.update.rollback.path") else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let allowedRoot = support.appendingPathComponent("PersonalAgent/AgentOSUpdateRollback", isDirectory: true).standardizedFileURL
            let candidate = URL(fileURLWithPath: savedPath).standardizedFileURL
            guard candidate.path.hasPrefix(allowedRoot.path + "/"),
                  FileManager.default.fileExists(atPath: candidate.appendingPathComponent("rollback.json").path) else { return }
            let record = try JSONDecoder().decode(AgentOSRollbackRecord.self, from: Data(contentsOf: candidate.appendingPathComponent("rollback.json")))
            guard record.manifest.revision == UserDefaults.standard.string(forKey: "agentos.update.revision") else { return }
            rollbackDirectory = candidate
            activeManifest = record.manifest
        } catch {
            status = "Không thể khôi phục trạng thái rollback đã lưu."
        }
    }

    private func validateDefinitionPayloads(_ updates: [(String, String)], workspaceRoot: URL) throws {
        let replacementByPath = Dictionary(uniqueKeysWithValues: updates.map { ($0.0.lowercased(), $0.1) })
        let fileManager = FileManager.default

        var skillTexts: [String: String] = [:]
        let skillDirectory = workspaceRoot.appendingPathComponent("Skills", isDirectory: true)
        if fileManager.fileExists(atPath: skillDirectory.path) {
            for url in try fileManager.contentsOfDirectory(at: skillDirectory, includingPropertiesForKeys: nil)
                where url.pathExtension.lowercased() == "md" {
                let path = "skills/" + url.lastPathComponent
                if let replacement = replacementByPath[path.lowercased()] {
                    skillTexts[path.lowercased()] = replacement
                } else {
                    skillTexts[path.lowercased()] = try String(contentsOf: url, encoding: .utf8)
                }
            }
        }
        for (path, text) in updates where path.lowercased().hasPrefix("skills/")
            && URL(fileURLWithPath: path).pathExtension.lowercased() == "md" {
            skillTexts[path.lowercased()] = text
        }
        var agentTexts: [String: String] = [:]
        let agentDirectory = workspaceRoot.appendingPathComponent("Agents", isDirectory: true)
        if fileManager.fileExists(atPath: agentDirectory.path) {
            for url in try fileManager.contentsOfDirectory(at: agentDirectory, includingPropertiesForKeys: nil)
                where url.pathExtension.lowercased() == "md" {
                let path = "agents/" + url.lastPathComponent
                if let replacement = replacementByPath[path.lowercased()] {
                    agentTexts[path.lowercased()] = replacement
                } else {
                    agentTexts[path.lowercased()] = try String(contentsOf: url, encoding: .utf8)
                }
            }
        }
        for (path, text) in updates where path.lowercased().hasPrefix("agents/")
            && URL(fileURLWithPath: path).pathExtension.lowercased() == "md" {
            agentTexts[path.lowercased()] = text
        }
        try AgentOSSoftUpdateDefinitionValidator.validate(
            skillMarkdowns: Array(skillTexts.values),
            agentMarkdowns: Array(agentTexts.values)
        )
    }

    private func rollback() async {
        guard let rollbackDirectory, let manifest = activeManifest else { return }
        busy = true
        defer { busy = false }
        do {
            let workspace = try LocalAgentWorkspace.documents()
            let workspaceRoot = await workspace.rootURL
            let record = try JSONDecoder().decode(AgentOSRollbackRecord.self, from: Data(contentsOf: rollbackDirectory.appendingPathComponent("rollback.json")))
            guard record.manifest == manifest else { throw AgentOSSoftUpdateError.invalidManifest }
            for item in manifest.files {
                let target = workspaceRoot.appendingPathComponent(item.path).standardizedFileURL
                guard target.path.hasPrefix(workspaceRoot.standardizedFileURL.path + "/"),
                      FileManager.default.fileExists(atPath: target.path) else {
                    throw AgentOSSoftUpdateError.localConflict(item.path)
                }
                let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
                guard (attrs[.type] as? FileAttributeType) == .typeRegular,
                      AgentOSSoftUpdateClient.sha256Hex(try Data(contentsOf: target)).caseInsensitiveCompare(item.sha256) == .orderedSame else {
                    throw AgentOSSoftUpdateError.localConflict(item.path)
                }
            }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let snapshots = try DurableWorkspaceSnapshotStore(directoryURL: support.appendingPathComponent("PersonalAgent/AgentOSSnapshots", isDirectory: true))
            let safety = try await snapshots.createSnapshot(of: workspaceRoot)
            do {
                for item in manifest.files {
                    if record.missingPaths.contains(item.path) {
                        try await workspace.remove(at: item.path)
                    } else {
                        let backup = rollbackDirectory.appendingPathComponent(item.path).standardizedFileURL
                        guard backup.path.hasPrefix(rollbackDirectory.standardizedFileURL.path + "/") else {
                            throw AgentOSSoftUpdateError.unsafePath(item.path)
                        }
                        let data = try Data(contentsOf: backup)
                        guard let baseHash = item.baseSHA256, baseHash != "missing",
                              AgentOSSoftUpdateClient.sha256Hex(data).caseInsensitiveCompare(baseHash) == .orderedSame else {
                            throw AgentOSSoftUpdateError.hashMismatch(item.path)
                        }
                        let target = workspaceRoot.appendingPathComponent(item.path).standardizedFileURL
                        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: target, options: .atomic)
                    }
                }
            } catch {
                try await snapshots.restore(snapshotID: safety.id, to: workspaceRoot)
                throw error
            }
            UserDefaults.standard.set(manifest.baseRevision, forKey: "agentos.update.revision")
            try? FileManager.default.removeItem(at: rollbackDirectory)
            self.rollbackDirectory = nil
            activeManifest = nil
            UserDefaults.standard.removeObject(forKey: "agentos.update.rollback.path")
            await session.refresh()
            status = "Đã khôi phục các tệp đã cập nhật; tệp khác được giữ nguyên."
        } catch {
            status = "Khôi phục bị chặn để bảo vệ chỉnh sửa cục bộ: \\(error.localizedDescription)"
        }
    }
}

private struct AgentOSRollbackRecord: Codable {
    let manifest: AgentOSSoftUpdateManifest
    let missingPaths: [String]
}

private struct ImportedFilePreview: Identifiable {
    let id: UUID
    let title: String
    let text: String
}

private enum CredentialState: Equatable {
    case unknown, saved, missing, error(String)
}

private enum ConnectionState: Equatable {
    case idle, testing, success, failure(String)
}

private extension SettingsScreen {
    var credentialAccount: String { "provider.api-key.\(remoteProvider)" }

    func loadCredentialState(for provider: String) -> CredentialState {
        do {
            guard let data = try KeychainSecretStore().load(account: "provider.api-key.\(provider)"),
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return .missing
            }
            return .saved
        } catch {
            return .error("Keychain read failed.")
        }
    }

    func saveProviderCredential() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasExistingCredential = credentialState == .saved
        guard !value.isEmpty || hasExistingCredential else { return }
        if remoteProvider == "openai-compatible" {
            let endpoint = compatibleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = compatibleModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !endpoint.isEmpty, !model.isEmpty else {
                credentialState = .error("Endpoint and model are required.")
                return
            }
            UserDefaults.standard.set(endpoint, forKey: "provider.compatible.endpoint")
            UserDefaults.standard.set(model, forKey: "provider.compatible.model")
        }
        do {
            if !value.isEmpty {
                try KeychainSecretStore().store(
                    account: credentialAccount,
                    secret: Data(value.utf8)
                )
            }
            apiKey = ""
            credentialState = .saved
            connectionState = .idle
            clearProviderConnectionTest()
            UserDefaults.standard.set(remoteProvider, forKey: "provider.remote.id")
            UserDefaults.standard.set(true, forKey: "provider.remote.enabled")
            UserDefaults.standard.set("remote", forKey: "provider.execution.mode")
            Task { await session.refresh() }
        } catch {
            credentialState = .error("Could not save API key securely.")
        }
    }

    func deleteProviderCredential() {
        do {
            try KeychainSecretStore().delete(account: credentialAccount)
            credentialState = .missing
            connectionState = .idle
            clearProviderConnectionTest()
            apiKey = ""
            UserDefaults.standard.set(false, forKey: "provider.remote.enabled")
            UserDefaults.standard.set("local", forKey: "provider.execution.mode")
            Task { await session.refresh() }
        } catch {
            credentialState = .error("Could not delete API key.")
        }
    }

    @MainActor
    func refreshOpenRouterModels() async {
        let endpoint = compatibleEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.localizedCaseInsensitiveContains("openrouter.ai") else {
            openRouterModelsMessage = "Set the endpoint to OpenRouter before refreshing its model catalog."
            return
        }
        let entered = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let token: String
        if !entered.isEmpty {
            token = entered
        } else {
            do {
                guard let data = try KeychainSecretStore().load(account: credentialAccount),
                      let saved = String(data: data, encoding: .utf8), !saved.isEmpty else {
                    openRouterModelsMessage = "Save an OpenRouter API key first."
                    return
                }
                token = saved
            } catch {
                openRouterModelsMessage = "Could not read the saved API key from Keychain."
                return
            }
        }
        isRefreshingOpenRouterModels = true
        openRouterModelsMessage = nil
        defer { isRefreshingOpenRouterModels = false }
        do {
            let response = try await SecurityNetworkTransport(network: URLSessionNetworkAccess()).send(
                ProviderTransportRequest(
                    url: "https://openrouter.ai/api/v1/models",
                    method: "GET",
                    headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"]
                )
            )
            guard (200..<300).contains(response.statusCode),
                  let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let rows = payload["data"] as? [[String: Any]] else {
                openRouterModelsMessage = "OpenRouter model catalog request failed (HTTP \(response.statusCode))."
                return
            }
            let catalogModels = rows.compactMap { row -> OpenRouterModelOption? in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return OpenRouterModelOption(id: id, name: (name?.isEmpty == false ? name! : id))
            }
            // The free router is a first-class model alias and may not be returned
            // by the concrete-model catalog endpoint, so always expose it explicitly.
            let freeRouter = OpenRouterModelOption(id: "openrouter/free", name: "Free Models Router")
            let uniqueCatalog = catalogModels.filter { $0.id != freeRouter.id }
            openRouterModels = [freeRouter] + Array(
                uniqueCatalog
                    .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
                    .prefix(499)
            )
            guard !openRouterModels.isEmpty else {
                openRouterModelsMessage = "OpenRouter returned no usable model IDs."
                return
            }
            if !openRouterModels.contains(where: { $0.id == compatibleModel }) {
                compatibleModel = openRouterModels.first?.id ?? compatibleModel
            }
            UserDefaults.standard.set(compatibleEndpoint, forKey: "provider.compatible.endpoint")
            UserDefaults.standard.set(compatibleModel, forKey: "provider.compatible.model")
            openRouterModelsMessage = "Loaded \(openRouterModels.count) models. Save configuration to apply it to chat."
        } catch {
            openRouterModelsMessage = "Could not refresh OpenRouter models. Check network and API key."
        }
    }

    func clearProviderConnectionTest() {
        UserDefaults.standard.removeObject(forKey: "provider.connection.test.provider")
        UserDefaults.standard.removeObject(forKey: "provider.connection.test.result")
    }

    func recordProviderConnectionTest(success: Bool) {
        UserDefaults.standard.set(remoteProvider, forKey: "provider.connection.test.provider")
        UserDefaults.standard.set(success ? "success" : "failure", forKey: "provider.connection.test.result")
    }

    func testProviderConnection() async {
        // A successful /models request does not prove chat completions work.
        // Test the same runtime route that Chat uses, with the saved Keychain credential.
        saveProviderCredential()
        if case .error = credentialState {
            connectionState = .failure("Save the provider configuration before testing.")
            recordProviderConnectionTest(success: false)
            return
        }

        do {
            guard let data = try KeychainSecretStore().load(account: credentialAccount),
                  let saved = String(data: data, encoding: .utf8),
                  !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                connectionState = .failure("Save the provider configuration before testing.")
                recordProviderConnectionTest(success: false)
                return
            }
        } catch {
            connectionState = .failure("Could not read the saved API key.")
            recordProviderConnectionTest(success: false)
            return
        }

        guard !UserDefaults.standard.bool(forKey: "privacy.localOnly") else {
            connectionState = .failure(String(localized: "Remote provider testing is disabled while Local-only mode is on."))
            recordProviderConnectionTest(success: false)
            return
        }

        connectionState = .testing
        do {
            guard let runtime = session.composition.providerRuntime,
                  let model = runtime.identity.models.first?.id else {
                throw URLError(.unsupportedURL)
            }
            let response = try await runtime.complete(
                LLMRequest(
                    model: model,
                    prompt: "Reply with OK."
                )
            )
            guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            await MainActor.run {
                connectionState = .success
                recordProviderConnectionTest(success: true)
            }
        } catch {
            await MainActor.run {
                connectionState = .failure("Chat completion failed. Check the key, model access, endpoint, and network.")
                recordProviderConnectionTest(success: false)
            }
        }
    }
}


// MARK: - AgentOS Storage Browser

/// Exposes only the user-editable text workspace. Credentials, model binaries, logs and cache
/// are deliberately outside the browsable roots.
private struct AgentOSStorageBrowserScreen: View {
    private let roots = ["agents", "skills", "modules", "tools", "workspace"]
    private let readableExtensions: Set<String> = ["md", "txt", "json", "yaml", "yml", "swift"]
    @State private var workspace: LocalAgentWorkspace?
    @State private var root = "workspace"
    @State private var currentPath = "workspace"
    @State private var entries: [AgentWorkspaceEntry] = []
    @State private var query = ""
    @State private var searchResults: [String] = []
    @State private var selectedFile: String?
    @State private var editorText = ""
    @State private var isEditing = false
    @State private var newFileName = ""
    @State private var showCreateFile = false
    @State private var status: String?
    @State private var isBusy = false

    private var visibleEntries: [AgentWorkspaceEntry] {
        let filtered = query.isEmpty ? entries : entries.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
        }
        return filtered.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    var body: some View {
        ScreenScaffold(title: "AgentOS Storage", systemImage: "externaldrive") {
            GlassPanel {
                Text("Allowed workspace roots")
                    .font(.headline)
                Picker("Root", selection: $root) {
                    ForEach(roots, id: \.self) { item in
                        Text(item.capitalized).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: root) { _, value in
                    currentPath = value
                    query = ""
                    searchResults = []
                    Task { await loadDirectory() }
                }
                HStack {
                    Text(currentPath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    Spacer()
                    Button {
                        showCreateFile = true
                    } label: {
                        Label("New Markdown", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                TextField("Filter current directory", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await searchContent() }
                } label: {
                    Label("Search file content", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            }

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            GlassPanel {
                if isBusy { ProgressView() }
                if !searchResults.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(searchResults, id: \.self) { path in
                            Button {
                                Task { await openFile(path) }
                            } label: {
                                Label(path, systemImage: "doc.text")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Clear search") { searchResults = [] }
                        .buttonStyle(.bordered)
                } else if visibleEntries.isEmpty {
                    Text("No files or folders here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleEntries, id: \.relativePath) { entry in
                            Button {
                                if entry.isDirectory {
                                    currentPath = entry.relativePath
                                    query = ""
                                    Task { await loadDirectory() }
                                } else {
                                    Task { await openFile(entry.relativePath) }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                                    Text(URL(fileURLWithPath: entry.relativePath).lastPathComponent)
                                        .lineLimit(2)
                                    Spacer()
                                    if entry.isDirectory {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if currentPath != root {
                    Button {
                        let parent = (currentPath as NSString).deletingLastPathComponent
                        currentPath = parent.isEmpty ? root : parent
                        query = ""
                        Task { await loadDirectory() }
                    } label: {
                        Label("Parent folder", systemImage: "arrow.up.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task { await loadDirectory() }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                VStack(spacing: 12) {
                    if let selectedFile {
                        Text(selectedFile)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    TextEditor(text: $editorText)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                }
                .navigationTitle("Edit text file")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await saveFile() } }
                            .disabled(isBusy)
                    }
                }
            }
        }
        .alert("Create Markdown file", isPresented: $showCreateFile) {
            TextField("filename.md", text: $newFileName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { newFileName = "" }
            Button("Create") { Task { await createFile() } }
        } message: {
            Text("Creates a new .md file in the current allowed folder.")
        }
    }

    @MainActor
    private func ensureWorkspace() async throws -> LocalAgentWorkspace {
        if let workspace { return workspace }
        let created = try LocalAgentWorkspace.documents()
        try await created.prepare()
        workspace = created
        return created
    }

    @MainActor
    private func loadDirectory() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let store = try await ensureWorkspace()
            guard isAllowed(currentPath) else { throw AgentWorkspaceError.invalidPath(currentPath) }
            entries = try await store.listDirectory(at: currentPath)
                .filter { isAllowed($0.relativePath) && !WorkspaceContentSafety.isProtectedPath($0.relativePath) }
            status = "\(entries.count) entries · local workspace"
        } catch {
            entries = []
            status = "Could not read workspace: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func openFile(_ path: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            guard isAllowed(path),
                  !WorkspaceContentSafety.isProtectedPath(path),
                  readableExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
                throw AgentWorkspaceError.invalidPath(path)
            }
            let store = try await ensureWorkspace()
            let metadata = try await store.metadata(at: path)
            guard !metadata.isDirectory, metadata.byteCount <= 512 * 1024 else {
                throw AgentWorkspaceError.ioFailure("File is too large to preview (limit 512 KiB).")
            }
            let text = try await store.readFile(at: path)
            guard !WorkspaceContentSafety.containsPotentialSecret(text) else {
                throw AgentWorkspaceError.ioFailure("Sensitive content is not available in Storage Browser.")
            }
            selectedFile = path
            editorText = text
            status = "Read \(metadata.byteCount) bytes; ready to edit."
            isEditing = true
        } catch {
            status = "Read failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveFile() async {
        guard let selectedFile, isAllowed(selectedFile),
              readableExtensions.contains(URL(fileURLWithPath: selectedFile).pathExtension.lowercased()) else {
            status = "Save rejected: unsupported path or file type."
            return
        }
        guard editorText.utf8.count <= 512 * 1024 else {
            status = "Save rejected: text exceeds 512 KiB."
            return
        }
        guard !WorkspaceContentSafety.containsPotentialSecret(editorText) else {
            status = "Save rejected: sensitive content is not allowed in Storage Browser."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let store = try await ensureWorkspace()
            try await store.writeFile(editorText, to: selectedFile)
            let persisted = try await store.readFile(at: selectedFile)
            guard persisted == editorText else {
                throw AgentWorkspaceError.ioFailure("Read-back verification did not match the saved content.")
            }
            status = "Saved and verified: \(selectedFile)"
            isEditing = false
            await loadDirectory()
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func createFile() async {
        let name = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFileName = ""
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
              URL(fileURLWithPath: name).pathExtension.lowercased() == "md",
              !WorkspaceContentSafety.isProtectedPath(name),
              isAllowed(currentPath) else {
            status = "Use a simple filename ending in .md."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let store = try await ensureWorkspace()
            let path = currentPath + "/" + name
            guard try await store.exists(at: path) == false else {
                status = "File already exists: \(path)"
                return
            }
            try await store.writeFile("", to: path)
            guard try await store.readFile(at: path).isEmpty else {
                throw AgentWorkspaceError.ioFailure("New file read-back verification failed.")
            }
            status = "Created and verified: \(path)"
            await loadDirectory()
        } catch {
            status = "Create failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func searchContent() async {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        searchResults = []
        do {
            let store = try await ensureWorkspace()
            var queue: [(String, Int)] = roots.map { ($0, 0) }
            var visited = 0
            var matches: [String] = []
            while !queue.isEmpty && visited < 500 && matches.count < 50 {
                let (directory, depth) = queue.removeFirst()
                guard isAllowed(directory) else { continue }
                let children = try await store.listDirectory(at: directory)
                for child in children where isAllowed(child.relativePath)
                    && !WorkspaceContentSafety.isProtectedPath(child.relativePath) {
                    visited += 1
                    if child.isDirectory {
                        if depth < 5 { queue.append((child.relativePath, depth + 1)) }
                    } else if readableExtensions.contains(URL(fileURLWithPath: child.relativePath).pathExtension.lowercased()) {
                        let metadata = try await store.metadata(at: child.relativePath)
                        guard metadata.byteCount <= 256 * 1024 else { continue }
                        let text = try await store.readFile(at: child.relativePath)
                        guard !WorkspaceContentSafety.containsPotentialSecret(text) else { continue }
                        if text.localizedCaseInsensitiveContains(needle) {
                            matches.append(child.relativePath)
                            if matches.count >= 50 { break }
                        }
                    }
                    if visited >= 500 { break }
                }
            }
            searchResults = matches
            status = "Search checked up to \(visited) entries; found \(matches.count) matches."
        } catch {
            status = "Search failed: \(error.localizedDescription)"
        }
    }

    private func isAllowed(_ path: String) -> Bool {
        // FileBackedSkillStore/AgentStore historically use title-cased directory names,
        // while LocalAgentWorkspace prepares lowercase aliases. Filesystem casing varies
        // by platform, so compare roots case-insensitively and preserve the actual path.
        let normalized = path.lowercased()
        return roots.contains {
            normalized == $0.lowercased()
                || normalized.hasPrefix($0.lowercased() + "/")
        }
    }
}
