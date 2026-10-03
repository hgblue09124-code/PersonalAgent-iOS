import SwiftUI
import UniformTypeIdentifiers
import PAProviders
import PAComposition
import UIKit
import Security

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var isImportingGGUF = false
    @State private var lastImportError: String?
    @AppStorage("app.language") private var appLanguage = "vi"
    @State private var updateState: UpdateState = .idle
    @State private var copiedUpdateLink = false
    @State private var remoteProvider = UserDefaults.standard.string(forKey: "provider.remote.id") ?? "openai"
    @State private var apiKey = ""
    @State private var credentialState: CredentialState = .unknown
    @State private var connectionState: ConnectionState = .idle

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
                Label("Remote Provider", systemImage: "server.rack")
                    .font(.headline)

                Picker("Provider", selection: $remoteProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Grok").tag("grok")
                }
                .pickerStyle(.segmented)
                .onChange(of: remoteProvider) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "provider.remote.id")
                    apiKey = ""
                    credentialState = loadCredentialState(for: newValue)
                    connectionState = .idle
                }

                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)

                HStack(spacing: 8) {
                    Button("Save") { saveProviderCredential() }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test connection") {
                        Task { await testProviderConnection() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connectionState == .testing)
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
        .id(appLanguage)
        .fileImporter(
            isPresented: $isImportingGGUF,
            allowedContentTypes: [
                UTType(filenameExtension: "gguf") ?? .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                guard selectedURL.pathExtension.lowercased() == "gguf" else {
                    lastImportError = "Chỉ hỗ trợ tệp GGUF."
                    return
                }
                Task {
                    lastImportError = nil
                    let scoped = selectedURL.startAccessingSecurityScopedResource()
                    defer { if scoped { selectedURL.stopAccessingSecurityScopedResource() } }
                    await session.importModel(from: selectedURL)
                    lastImportError = session.lastError
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
            let candidates = releases
                .filter(\.prerelease)
                .filter { release in
                    guard let channel = currentChannel, !channel.isEmpty else { return true }
                    return release.tag_name == channel
                }
                .compactMap { release -> (LatestRelease, String)? in
                    guard let code = release.preReleaseCode else { return nil }
                    return (release, code)
                }
                .sorted(by: { $0.0.created_at > $1.0.created_at })

            guard let (release, releasePreCode) = candidates.first else {
                updateState = .current
                return
            }

            guard currentPreReleaseCode != releasePreCode else {
                updateState = .current
                return
            }

            let downloadURL = release.assets.first(where: { $0.name == "PersonalAgent-unsigned.ipa" })?.browser_download_url
                ?? release.html_url
            copiedUpdateLink = false
            updateState = .available(releasePreCode, downloadURL)
        } catch {
            updateState = .failed
        }
    }
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PersonalAgent.Provider",
            kSecAttrAccount as String: "provider.api-key.\(provider)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else { return .error("Keychain read failed.") }
        return .saved
    }

    func saveProviderCredential() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            let data = Data(value.utf8)
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "PersonalAgent.Provider",
                kSecAttrAccount as String: credentialAccount
            ]
            let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = base
                item[kSecValueData as String] = data
                let addStatus = SecItemAdd(item as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw NSError(domain: "Keychain", code: Int(addStatus)) }
            } else if status != errSecSuccess {
                throw NSError(domain: "Keychain", code: Int(status))
            }
            apiKey = ""
            credentialState = .saved
            connectionState = .idle
            UserDefaults.standard.set(remoteProvider, forKey: "provider.remote.id")
        } catch {
            credentialState = .error("Could not save API key securely.")
        }
    }

    func deleteProviderCredential() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PersonalAgent.Provider",
            kSecAttrAccount as String: credentialAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            credentialState = .missing
            connectionState = .idle
            apiKey = ""
        } else {
            credentialState = .error("Could not delete API key.")
        }
    }

    func testProviderConnection() async {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        connectionState = .testing
        let endpoint: String
        let model: String
        switch remoteProvider {
        case "grok":
            endpoint = "https://api.x.ai/v1/chat/completions"
            model = "grok-3"
        default:
            endpoint = "https://api.openai.com/v1/chat/completions"
            model = "gpt-4o-mini"
        }
        do {
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": [["role": "user", "content": "Reply with OK."]],
                "max_tokens": 8,
                "temperature": 0
            ])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            await MainActor.run { connectionState = .success }
        } catch {
            await MainActor.run { connectionState = .failure("Connection failed. Check the key and provider access.") }
        }
    }
}
