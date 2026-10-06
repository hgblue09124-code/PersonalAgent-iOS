import SwiftUI
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
                            roadmapCard("Voice", "Talk naturally", "waveform", "Soon")
                            roadmapCard("Vision", "Understand images", "eye", "Soon")
                            roadmapCard("Web research", "Search & synthesize", "globe", "Soon")
                            roadmapCard("Long context", "Handle larger conversations", "text.alignleft", "Soon")
                            roadmapCard("RAG", "Ground answers in knowledge", "books.vertical", "Soon")
                            roadmapCard("Local embeddings", "Semantic retrieval on device", "square.stack.3d.up", "Soon")
                        }

                        roadmapGroup("Agent OS") {
                            roadmapCard("Automations", "Run recurring work", "arrow.triangle.2.circlepath", "Soon")
                            roadmapCard("Tools", "Connect capabilities", "wrench.and.screwdriver", "Soon")
                            roadmapCard("Multi-agent", "Delegate subtasks", "person.3", "Soon")
                            roadmapCard("Plans", "Break goals into steps", "list.number", "Soon")
                            roadmapCard("Approvals", "Ask before sensitive actions", "checkmark.shield", "Soon")
                            roadmapCard("Agent policies", "Control what agents can do", "slider.horizontal.3", "Soon")
                            roadmapCard("Skill marketplace", "Discover and install skills", "square.grid.2x2", "Soon")
                        }

                        roadmapGroup("Connected workspace") {
                            roadmapCard("Files", "Work with documents", "doc.text", "Soon")
                            roadmapCard("Calendar", "Plan your time", "calendar", "Soon")
                            roadmapCard("Notifications", "Stay in the loop", "bell", "Soon")
                            roadmapCard("Email", "Read and act on mail", "envelope", "Soon")
                            roadmapCard("Web actions", "Act across the web", "safari", "Soon")
                            roadmapCard("Home", "Control connected devices", "house", "Soon")
                        }

                        roadmapGroup("Platform") {
                            roadmapCard("Sync", "Continue everywhere", "icloud", "Soon")
                            roadmapCard("Privacy center", "Control your data", "lock.shield", "Soon")
                            roadmapCard("Encrypted backup", "Protect agent state", "externaldrive.badge.icloud", "Soon")
                            roadmapCard("Export", "Take your data with you", "square.and.arrow.up", "Soon")
                            roadmapCard("Developer API", "Build on the Agent runtime", "chevron.left.forwardslash.chevron.right", "Soon")
                            roadmapCard("Extensions", "Add native capabilities", "puzzlepiece.extension", "Soon")
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

    private func roadmapCard(_ title: String, _ subtitle: String, _ symbol: String, _ badge: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.08), in: Capsule())
            }
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.primary.opacity(0.06), lineWidth: 1))
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