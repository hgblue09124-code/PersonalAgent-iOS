import SwiftUI
import PAComposition

struct RootView: View {
    @ObservedObject var session: KernelSession
    @State private var showWorkspace = false

    var body: some View {
        ZStack {
            AgentScreen(session: session)

            VStack {
                HStack {
                    Button {
                        showWorkspace = true
                    } label: {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Open Agent workspace")

                    Spacer()
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .allowsHitTesting(true)
        }
        .sheet(isPresented: $showWorkspace) {
            AgentWorkspaceSheet(session: session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await session.refresh() }
    }
}

private struct AgentWorkspaceSheet: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent workspace")
                            .font(.title2.bold())
                        Text("Everything else stays contextual to the living Agent.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Capabilities") {
                    NavigationLink {
                        ModelsScreen(session: session)
                    } label: {
                        workspaceRow("Models", "Local GGUF models", "cube.box")
                    }

                    NavigationLink {
                        ProvidersScreen(session: session)
                    } label: {
                        workspaceRow("Providers", "Remote and local providers", "server.rack")
                    }

                    NavigationLink {
                        SkillsScreen(session: session)
                    } label: {
                        workspaceRow("Skills", "Available capabilities", "puzzlepiece")
                    }

                    NavigationLink {
                        MemoryScreen(session: session)
                    } label: {
                        workspaceRow("Memory", "Persistent agent memory", "brain")
                    }
                }

                Section("System") {
                    NavigationLink {
                        SettingsScreen(session: session)
                    } label: {
                        workspaceRow("Settings", "Agent and device configuration", "gearshape")
                    }
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func workspaceRow(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .frame(width: 28)
        }
    }
}
