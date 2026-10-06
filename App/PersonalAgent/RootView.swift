import SwiftUI
import Foundation
import CryptoKit
import PASecurity
import UniformTypeIdentifiers
import PhotosUI
import Vision
import UIKit
import PAComposition

struct RootView: View {
    @ObservedObject var session: KernelSession
    @State private var showWorkspace = false
    @AppStorage("app.language") private var appLanguage = "vi"

    var body: some View {
        GeometryReader { proxy in
            AgentScreen(session: session, showWorkspace: $showWorkspace)
                .padding(.top, proxy.safeAreaInsets.top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.locale, Locale(identifier: appLanguage))
        .environment(\.kernelSession, session)
        .id(appLanguage)
        .sheet(isPresented: $showWorkspace) {
            AgentWorkspaceSheet(session: session)
        }
        .task { await session.refresh() }
        .onOpenURL { url in
            if url.scheme == "personalagent", url.host == "chat",
               let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "text" })?.value {
                Task { await session.submitGoal(text) }
                return
            }
            guard url.pathExtension.lowercased() == "gguf" else { return }
            Task {
                let securityScoped = url.startAccessingSecurityScopedResource()
                defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
                await session.importModel(from: url)
            }
        }
    }
}

private struct AgentWorkspaceSheet: View {
    @ObservedObject var session: KernelSession
    @State private var workspaceExpanded = false
    @State private var appeared = false
    @State private var selectedRoadmapFeature: RoadmapFeature?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.title3.bold())
                            .frame(width: 40, height: 40)
                            .background(.thinMaterial, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Living workspace").font(.headline)
                            Text("Every product capability has a native surface.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { workspaceExpanded.toggle() }
                        } label: {
                            Image(systemName: workspaceExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption.bold()).frame(width: 34, height: 34)
                                .background(.secondary.opacity(0.10), in: Circle())
                        }.buttonStyle(.plain)
                    }.padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Agent workspace")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Chat, execution, models, providers, skills, memory and settings are available without leaving the Agent.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Live status") {
                    HStack(spacing: 8) {
                        statusPill("Agent", session.state.lifecycle.rawValue, "sparkles")
                        statusPill("Provider", session.providerLifecycle, "server.rack")
                        statusPill("Models", "\(session.installedModels.count)", "cube.box")
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Core") {
                    workspaceLink("Chat", "Conversations and persistent chat history", "bubble.left.and.bubble.right") {
                        ChatScreen(session: session)
                    }
                    workspaceLink("Tasks", "Live execution, results and errors", "checklist") {
                        TasksScreen(session: session)
                    }
                }

                Section("Capabilities") {
                    workspaceLink("Models", "Local GGUF models and runtime lifecycle", "cube.box") {
                        ModelsScreen(session: session)
                    }
                    workspaceLink("Providers", "Remote and local inference adapters", "server.rack") {
                        ProvidersScreen(session: session)
                    }
                    workspaceLink("Skills", "Declared Skill.md capabilities", "puzzlepiece") {
                        SkillsScreen(session: session)
                    }
                    workspaceLink("Agents", "Agent.md profiles and scoped Skills", "person.crop.circle.badge.checkmark") {
                        AgentsScreen(session: session)
                    }
                    workspaceLink("Memory", "Persistent contextual memory", "brain") {
                        MemoryScreen()
                    }
                }

                Section("System") {
                    workspaceLink("Settings", "Model, provider credentials, language and runtime", "gearshape") {
                        SettingsScreen(session: session)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Coming soon").font(.title3.weight(.bold))
                                Text("The next layer of the Agent OS").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("ROADMAP").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                        }
                        roadmapGroup("Intelligence") {
                            roadmapCard(.voice)
                            roadmapCard(.vision)
                            roadmapCard(.webResearch)
                            roadmapCard(.longContext)
                            roadmapCard(.rag)
                            roadmapCard(.localEmbeddings)
                        }

                        roadmapGroup("Agent OS") {
                            roadmapCard(.automations)
                            roadmapCard(.tools)
                            roadmapCard(.multiAgent)
                            roadmapCard(.plans)
                            roadmapCard(.approvals)
                            roadmapCard(.agentPolicies)
                            roadmapCard(.skillMarketplace)
                        }

                        roadmapGroup("Connected workspace") {
                            roadmapCard(.files)
                            roadmapCard(.calendar)
                            roadmapCard(.notifications)
                            roadmapCard(.email)
                            roadmapCard(.webActions)
                            roadmapCard(.home)
                        }

                        roadmapGroup("Platform") {
                            roadmapCard(.sync)
                            roadmapCard(.privacyCenter)
                            roadmapCard(.encryptedBackup)
                            roadmapCard(.export)
                            roadmapCard(.developerAPI)
                            roadmapCard(.extensions)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.84), value: appeared)
            .onAppear { appeared = true }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(workspaceExpanded ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedRoadmapFeature) { feature in
            RoadmapFeatureScreen(feature: feature, session: session)
        }
    }

    private func statusPill(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.caption.bold())
            Text(title).font(.caption2.weight(.bold))
            Text(value).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    @ViewBuilder
    private func roadmapGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                content()
            }
        }
    }

    private func roadmapCard(_ feature: RoadmapFeature) -> some View {
        Button { selectedRoadmapFeature = feature } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Image(systemName: feature.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Text(feature.stateTitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(feature.isNative ? .green : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.08), in: Capsule())
                }
                Text(feature.title).font(.subheadline.weight(.semibold))
                Text(feature.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func workspaceLink<Destination: View>(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
    }
}

private struct MilestoneKey: EnvironmentKey {
    static let defaultValue: MilestoneGate = .m0
}

extension EnvironmentValues {
    var milestoneGate: MilestoneGate {
        get { self[MilestoneKey.self] }
        set { self[MilestoneKey.self] = newValue }
    }
}

private struct KernelSessionEnvironmentKey: EnvironmentKey {
    static let defaultValue: KernelSession? = nil
}

extension EnvironmentValues {
    var kernelSession: KernelSession? {
        get { self[KernelSessionEnvironmentKey.self] }
        set { self[KernelSessionEnvironmentKey.self] = newValue }
    }
}
private enum RoadmapFeature: String, CaseIterable, Identifiable {
    case voice, vision, webResearch, longContext, rag, localEmbeddings
    case automations, tools, multiAgent, plans, approvals, agentPolicies, skillMarketplace
    case files, calendar, notifications, email, webActions, home
    case sync, privacyCenter, encryptedBackup, export, developerAPI, extensions

    var id: String { rawValue }
    var title: String { rawValue == "webResearch" ? "Web research" : rawValue == "localEmbeddings" ? "Local embeddings" : rawValue == "multiAgent" ? "Multi-agent" : rawValue == "agentPolicies" ? "Agent policies" : rawValue == "skillMarketplace" ? "Skill marketplace" : rawValue == "privacyCenter" ? "Privacy center" : rawValue == "encryptedBackup" ? "Encrypted backup" : rawValue == "developerAPI" ? "Developer API" : rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .voice: "Talk naturally"; case .vision: "Understand images"; case .webResearch: "Search and synthesize"
        case .longContext: "Handle larger conversations"; case .rag: "Ground answers in knowledge"; case .localEmbeddings: "Semantic retrieval on device"
        case .automations: "Run recurring work"; case .tools: "Connect capabilities"; case .multiAgent: "Delegate subtasks"
        case .plans: "Break goals into steps"; case .approvals: "Ask before sensitive actions"; case .agentPolicies: "Control what agents can do"
        case .skillMarketplace: "Discover and install skills"; case .files: "Work with documents"; case .calendar: "Plan your time"
        case .notifications: "Stay in the loop"; case .email: "Read and act on mail"; case .webActions: "Act across the web"
        case .home: "Control connected devices"; case .sync: "Continue everywhere"; case .privacyCenter: "Control your data"
        case .encryptedBackup: "Protect agent state"; case .export: "Take your data with you"; case .developerAPI: "Build on the Agent runtime"
        case .extensions: "Add native capabilities"
        }
    }
    var symbol: String {
        switch self {
        case .voice: "waveform"; case .vision: "eye"; case .webResearch: "globe"; case .longContext: "text.alignleft"
        case .rag: "books.vertical"; case .localEmbeddings: "square.stack.3d.up"; case .automations: "arrow.triangle.2.circlepath"
        case .tools: "wrench.and.screwdriver"; case .multiAgent: "person.3"; case .plans: "list.number"
        case .approvals: "checkmark.shield"; case .agentPolicies: "slider.horizontal.3"; case .skillMarketplace: "square.grid.2x2"
        case .files: "doc.text"; case .calendar: "calendar"; case .notifications: "bell"; case .email: "envelope"
        case .webActions: "safari"; case .home: "house"; case .sync: "icloud"; case .privacyCenter: "lock.shield"
        case .encryptedBackup: "externaldrive.badge.icloud"; case .export: "square.and.arrow.up"; case .developerAPI: "chevron.left.forwardslash.chevron.right"
        case .extensions: "puzzlepiece.extension"
        }
    }
    var isNative: Bool { [.tools, .files, .export, .privacyCenter].contains(self) }
    var stateTitle: String { isNative ? "Native" : "Contract" }
}
private struct RoadmapFeatureScreen: View {
    let feature: RoadmapFeature
    @ObservedObject var session: KernelSession
    @AppStorage("privacy.localOnly") private var localOnly = true
    @AppStorage("privacy.persistChat") private var persistChat = true
    @State private var exportPayload = ""
    @State private var showExport = false
    @State private var showFileImporter = false
    @State private var indexedFileName: String?
    @State private var selectedImage: PhotosPickerItem?
    @State private var visionText = ""
    @State private var ragQuery = ""
    @State private var ragResults: [String] = []

    var body: some View {
        ScreenScaffold(title: feature.title, systemImage: feature.symbol) {
            GlassPanel {
                Label(feature.isNative ? "Native capability" : "Runtime contract", systemImage: feature.isNative ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.headline)
                Text(feature.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text(feature.isNative ? "Connected to an existing product boundary." : "Declared in the Agent OS surface; execution remains fail-closed until its adapter is installed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch feature {
            case .tools, .skillMarketplace, .extensions:
                SkillsScreen(session: session)
            case .multiAgent:
                AgentsScreen(session: session)
            case .plans, .automations:
                TasksScreen(session: session)
            case .longContext:
                ChatScreen(session: session)
            case .localEmbeddings:
                ModelsScreen(session: session)
            case .tools:
                SkillsScreen(session: session)
            case .vision:
                GlassPanel {
                    Label("On-device vision", systemImage: "eye")
                        .font(.headline)
                    PhotosPicker(selection: $selectedImage, matching: .images) {
                        Label("Choose image", systemImage: "photo")
                    }
                    .buttonStyle(.borderedProminent)
                    if !visionText.isEmpty {
                        Text(visionText)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
                .task(id: selectedImage) {
                    guard let selectedImage,
                          let data = try? await selectedImage.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let cgImage = image.cgImage else { return }
                    visionText = await recognizeText(in: cgImage)
                }
            case .rag:
                GlassPanel {
                    Label("Memory-grounded retrieval", systemImage: "books.vertical")
                        .font(.headline)
                    TextField("Ask the knowledge memory…", text: $ragQuery)
                        .textFieldStyle(.roundedBorder)
                    Button("Retrieve") {
                        let query = ragQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty else { return }
                        Task {
                            ragResults = (try? await session.composition.memoryContext(for: query, limit: 8)) ?? []
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    ForEach(ragResults, id: \.self) { result in
                        Text(result)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case .files:
                GlassPanel {
                    Label("Document boundary", systemImage: "doc.text")
                        .font(.headline)
                    Text("Use the existing system document importer for local data. Imported content stays under the app's storage boundary.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    StatusRow(title: "Storage", value: "APP SANDBOX")
                    Button("Import document") { showFileImporter = true }
                        .buttonStyle(.borderedProminent)
                    if let indexedFileName {
                        StatusRow(title: "Indexed", value: indexedFileName)
                    }
                }
            case .encryptedBackup:
                GlassPanel {
                    Label("Encrypted backup", systemImage: "externaldrive.badge.icloud")
                        .font(.headline)
                    Text("Encrypt the current Agent export with a device-bound key before sharing.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Create encrypted backup") {
                        exportPayload = makeEncryptedBackup()
                        showExport = !exportPayload.isEmpty
                    }
                    .buttonStyle(.borderedProminent)
                    if !exportPayload.isEmpty {
                        ShareLink(item: exportPayload, subject: Text("Personal Agent encrypted backup"))
                            .buttonStyle(.bordered)
                    }
                }
            case .export:
                GlassPanel {
                    Label("Export Agent state", systemImage: "square.and.arrow.up")
                        .font(.headline)
                    Text("Export the current conversations and memory snapshot as portable JSON.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Prepare export") {
                        exportPayload = makeExportPayload()
                        showExport = true
                    }
                    .buttonStyle(.borderedProminent)
                    if !exportPayload.isEmpty {
                        ShareLink(item: exportPayload, subject: Text("Personal Agent export"), message: Text("Agent conversations and memory"))
                            .buttonStyle(.bordered)
                    }
                }
            case .privacyCenter:
                GlassPanel {
                    Label("Privacy controls", systemImage: "lock.shield")
                        .font(.headline)
                    Toggle("Local-only execution", isOn: $localOnly)
                    Toggle("Persist chat history", isOn: $persistChat)
                    Text("These controls are persisted locally. Remote execution remains disabled until an explicit provider credential is configured.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                GlassPanel {
                    StatusRow(title: "State", value: "CONTRACT")
                    StatusRow(title: "Boundary", value: "Agent OS")
                    StatusRow(title: "Execution", value: "FAIL CLOSED")
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            indexedFileName = url.lastPathComponent
            UserDefaults.standard.set(Data(data.prefix(256_000)), forKey: "roadmap.files.last.data")
        }
    }

    private func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func makeEncryptedBackup() -> String {
        let plain = makeExportPayload()
        guard let data = plain.data(using: .utf8) else { return "" }
        do {
            let store = KeychainSecretStore()
            let account = "agent.backup.key"
            let keyData: Data
            if let existing = try store.load(account: account) {
                keyData = existing
            } else {
                let generated = SymmetricKey(size: .bits256)
                keyData = generated.withUnsafeBytes { Data($0) }
                try store.store(account: account, secret: keyData)
            }
            let key = SymmetricKey(data: keyData)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return "" }
            return combined.base64EncodedString()
        } catch {
            return ""
        }
    }

    private func makeExportPayload() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct ExportEnvelope: Encodable {
            let exportedAt: Date
            let conversations: [ChatConversation]
            let memory: [ExportMemory]
        }
        struct ExportMemory: Encodable {
            let id: String
            let kind: String
            let content: String
        }
        let memory = session.memoryRecords.map { ExportMemory(id: $0.id, kind: $0.kind, content: $0.content) }
        let envelope = ExportEnvelope(exportedAt: Date(), conversations: session.conversations, memory: memory)
        guard let data = try? encoder.encode(envelope), let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"export_failed\"}"
        }
        return text
    }
}
