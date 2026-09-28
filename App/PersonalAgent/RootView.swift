import SwiftUI
import PAComposition

struct RootView: View {
    @ObservedObject var session: KernelSession
    @State private var showWorkspace = false
    @AppStorage("app.language") private var appLanguage = "en"

    var body: some View {
        ZStack(alignment: .topLeading) {
            AgentScreen(session: session)

            Button {
                showWorkspace = true
            } label: {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.20), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .padding(.leading, 20)
            .padding(.top, 10)
            .accessibilityLabel("Open Agent workspace")
        }
        .sheet(isPresented: $showWorkspace) {
            AgentWorkspaceSheet(session: session)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .environment(\.locale, Locale(identifier: appLanguage))
        .id(appLanguage)
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
                            Text("Tap a surface to expand it.").font(.caption).foregroundStyle(.secondary)
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
                        Text("Models, providers, skills, memory and settings appear here when you need them.")
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

                Section("Capabilities") {
                    workspaceLink("Models", "Local GGUF models", "cube.box") {
                        ModelsScreen(session: session)
                    }
                    workspaceLink("Providers", "Remote and local adapters", "server.rack") {
                        ProvidersScreen(session: session)
                    }
                    workspaceLink("Skills", "Agent capabilities", "puzzlepiece") {
                        SkillsScreen(session: session)
                    }
                    workspaceLink("Memory", "Persistent context", "brain") {
                        MemoryScreen()
                    }
                }

                Section("System") {
                    workspaceLink("Settings", "Agent and device configuration", "gearshape") {
                        SettingsScreen(session: session)
                    }
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
