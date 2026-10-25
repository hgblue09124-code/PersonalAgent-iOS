import SwiftUI
import Foundation
import CryptoKit
import PASecurity
import UniformTypeIdentifiers
import PhotosUI
import Vision
import UIKit
import PAComposition
import PAImportGateway

struct RootView: View {
    @ObservedObject var session: KernelSession
    @State private var showWorkspace = false
    @AppStorage("app.language") private var appLanguage = "vi"
    @AppStorage("ui.v2.enabled") private var isUIV2Enabled = false

    var body: some View {
        Group {
            if isUIV2Enabled {
                PersonalAgentV2Shell(session: session, showWorkspace: $showWorkspace)
            } else {
                AgentScreen(session: session, showWorkspace: $showWorkspace)
            }
        }
        .environment(\.locale, Locale(identifier: appLanguage))
        .environment(\.kernelSession, session)
        .sheet(isPresented: $showWorkspace) {
            AgentWorkspaceSheet(session: session)
        }
        .task {
            await session.refresh()
        }
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


private struct PersonalAgentV2Shell: View {
    @ObservedObject var session: KernelSession
    @Binding var showWorkspace: Bool

    var body: some View {
        TabView {
            NavigationStack {
                ChatScreen(session: session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showWorkspace = true } label: {
                                Image(systemName: "circle.hexagongrid.fill")
                            }
                            .accessibilityLabel("Open Agent workspace")
                        }
                    }
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack {
                TasksScreen(session: session)
            }
            .tabItem { Label("Tasks", systemImage: "checklist") }

            NavigationStack {
                PersonalAgentProfileScreen()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }

            NavigationStack {
                SettingsScreen(session: session)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(AgentDesign.accent)
    }
}

private struct PersonalAgentProfileScreen: View {
    @AppStorage("profile.displayName") private var displayName = "Personal Agent"
    @AppStorage("profile.bio") private var bio = "Your personal AI workspace."
    @AppStorage("profile.avatar.data") private var avatarData: Data = Data()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ScreenScaffold(title: "Profile", systemImage: "person.crop.circle") {
            GlassPanel {
                VStack(spacing: 14) {
                    Group {
                        if let image = UIImage(data: avatarData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                Circle().fill(AgentDesign.accent.opacity(0.12))
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AgentDesign.accent)
                            }
                        }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 1))

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Change profile photo", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Choose a photo from your library for your profile avatar.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("About").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: $bio)
                        .frame(minHeight: 84, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            GlassPanel {
                Label("Personal profile", systemImage: "person.text.rectangle")
                    .font(.headline)
                Text("Your name, bio and avatar are stored locally on this device. They do not change Agent permissions or execution behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                let target = CGSize(width: 512, height: 512)
                let renderer = UIGraphicsImageRenderer(size: target)
                let resized = renderer.image { _ in
                    let scale = max(target.width / image.size.width, target.height / image.size.height)
                    let width = image.size.width * scale
                    let height = image.size.height * scale
                    let rect = CGRect(x: (target.width - width) / 2, y: (target.height - height) / 2, width: width, height: height)
                    image.draw(in: rect)
                }
                if let compressed = resized.jpegData(compressionQuality: 0.78) {
                    avatarData = compressed
                }
            }
        }
    }
}

private struct AgentWorkspaceSheet: View {
    @ObservedObject var session: KernelSession
    @AppStorage("app.language") private var appLanguage = "vi"
    @State private var workspaceExpanded = false
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
                    workspaceLink("Terminal", "Sandboxed commands and workspace file operations", "terminal") {
                        TerminalScreen()
                    }
                    workspaceLink("Files", "Import, retain and preview supported document formats", "doc.badge.plus") {
                        ImportedFilesScreen()
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
                                Text("Agent OS roadmap").font(.title3.weight(.bold))
                                Text("Executable surfaces first; external adapters remain fail-closed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(RoadmapFeature.readyCount)/\(RoadmapFeature.allCases.count) READY")
                                .font(.caption2.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(.green)
                        }

                        HStack(spacing: 8) {
                            roadmapMetric("Ready", RoadmapFeature.readyCount, .green)
                            roadmapMetric("Contract", RoadmapFeature.contractCount, .secondary)
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
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, Locale(identifier: appLanguage))
        .id(appLanguage)
        .presentationDetents(workspaceExpanded ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedRoadmapFeature) { feature in
            RoadmapFeatureScreen(feature: feature, session: session)
        }
    }

    private func statusPill(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.caption.bold())
            Text(LocalizedStringKey(title)).font(.caption2.weight(.bold))
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
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                content()
            }
        }
    }

    private func roadmapMetric(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
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
                    Text(LocalizedStringKey(feature.stateTitle))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(feature.stateColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(feature.stateColor.opacity(0.10), in: Capsule())
                }
                Text(LocalizedStringKey(feature.title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(feature.subtitle)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                    Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(subtitle))
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

    enum State {
        case ready
        case contract

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .contract: return "Contract"
            }
        }

        var color: Color {
            switch self {
            case .ready: return .green
            case .contract: return .secondary
            }
        }
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .voice: "Voice"
        case .vision: "Vision"
        case .webResearch: "Web research"
        case .longContext: "Long context"
        case .rag: "RAG"
        case .localEmbeddings: "Local embeddings"
        case .automations: "Automations"
        case .tools: "Tools"
        case .multiAgent: "Multi-agent"
        case .plans: "Plans"
        case .approvals: "Approvals"
        case .agentPolicies: "Agent policies"
        case .skillMarketplace: "Skill marketplace"
        case .files: "Files"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        case .email: "Email"
        case .webActions: "Web actions"
        case .home: "Home"
        case .sync: "Sync"
        case .privacyCenter: "Privacy center"
        case .encryptedBackup: "Encrypted backup"
        case .export: "Export"
        case .developerAPI: "Developer API"
        case .extensions: "Extensions"
        }
    }
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
    var state: State {
        switch self {
        case .vision, .longContext, .rag, .multiAgent,
             .files, .encryptedBackup, .export, .privacyCenter:
            return .ready
        case .voice, .webResearch, .localEmbeddings, .automations, .tools, .plans,
             .approvals, .agentPolicies, .skillMarketplace, .calendar, .notifications,
             .email, .webActions, .home, .sync, .developerAPI, .extensions:
            return .contract
        }
    }

    var stateTitle: String { state.title }
    var stateColor: Color { state.color }
    var detailText: String {
        switch state {
        case .ready:
            return "This capability is wired to an existing native Agent surface and can be exercised now."
        case .contract:
            return "The product boundary is reserved, but the external adapter is not installed. Execution stays fail-closed."
        }
    }

    static var readyCount: Int { allCases.filter { $0.state == .ready }.count }
    static var contractCount: Int { allCases.filter { $0.state == .contract }.count }
}
private struct RoadmapFeatureScreen: View {
    let feature: RoadmapFeature
    @ObservedObject var session: KernelSession
    @AppStorage("app.language") private var appLanguage = "vi"
    @AppStorage("privacy.localOnly") private var localOnly = false
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
        ScreenScaffold(title: String(localized: String.LocalizationValue(feature.title), locale: Locale(identifier: appLanguage)), systemImage: feature.symbol) {
            GlassPanel {
                HStack(spacing: 10) {
                    Image(systemName: feature.state == .ready ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(feature.stateColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(feature.stateTitle))
                            .font(.headline)
                        Text(LocalizedStringKey(feature.state == .ready ? "Executable UI surface" : "Adapter boundary"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(LocalizedStringKey(feature.subtitle)).font(.subheadline).foregroundStyle(.secondary)
                Text(LocalizedStringKey(feature.detailText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .onChange(of: persistChat) { _, enabled in
                            session.setChatPersistence(enabled)
                        }
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
            if let text = String(data: data, encoding: .utf8).map({ String($0.prefix(256_000)) }) {
                Task {
                    await session.remember(
                        "Document \(url.lastPathComponent):\n\(text)",
                        kind: "context"
                    )
                }
            }
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

private struct ImportedFilesScreen: View {
    @State private var isImporting = false
    @State private var files: [ImportedFile] = []
    @State private var store: ImportedFileStore?
    @State private var selectedFile: ImportedFile?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Import any file from Files or another document provider. Original bytes are preserved; text extraction is available only for supported formats.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section("Import status") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                Section("Imported files · \(files.count)") {
                    if files.isEmpty {
                        ContentUnavailableView(
                            "No imported files",
                            systemImage: "doc.badge.plus",
                            description: Text("Tap + to import one or more files.")
                        )
                    } else {
                        ForEach(files) { file in
                            Button {
                                selectedFile = file
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.title2)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.originalName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text("\(file.fileExtension.isEmpty ? "unknown format" : file.fileExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    remove(file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import files")
                }
            }
        }
        .task { await reload() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importURLs(urls)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $selectedFile) { file in
            if let store {
                ImportedFilePreviewSheet(file: file, store: store)
            } else {
                Text("Import store is unavailable.")
            }
        }
    }

    @MainActor
    private func ensureStore() throws -> ImportedFileStore {
        if let store { return store }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support
            .appendingPathComponent("PersonalAgent", isDirectory: true)
            .appendingPathComponent("ImportedFiles", isDirectory: true)
        let created = try ImportedFileStore(directoryURL: directory)
        store = created
        return created
    }

    @MainActor
    private func reload() async {
        do {
            let target = try ensureStore()
            files = await target.listImports()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Unable to load imports: \(error.localizedDescription)")
        }
    }

    private func importURLs(_ urls: [URL]) {
        Task { @MainActor in
            do {
                let target = try ensureStore()
                var failures: [String] = []
                for url in urls {
                    let typeIdentifier: String?
                    do {
                        typeIdentifier = try url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
                    } catch {
                        typeIdentifier = nil
                    }
                    do {
                        _ = try await target.importFile(from: url, contentTypeIdentifier: typeIdentifier)
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await reload()
                if !failures.isEmpty {
                    errorMessage = failures.joined(separator: "\n")
                } else {
                    errorMessage = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ file: ImportedFile) {
        Task { @MainActor in
            do {
                let target = try ensureStore()
                try await target.removeImport(id: file.id)
                await reload()
            } catch {
                errorMessage = String(localized: "Unable to delete \(file.originalName): \(error.localizedDescription)")
            }
        }
    }
}

private struct ImportedFilePreviewSheet: View {
    let file: ImportedFile
    let store: ImportedFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var content: ImportedFileContent?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let content {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(content.format.rawValue, systemImage: "doc.text")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(content.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "doc.questionmark",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Reading file…")
                }
            }
            .navigationTitle(file.originalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                content = try await ImportedFileContentReader().read(file, from: store)
            } catch {
                errorMessage = String(localized: "The file was imported and preserved, but this build cannot extract a preview for it. \(error.localizedDescription)")
            }
        }
    }
}

