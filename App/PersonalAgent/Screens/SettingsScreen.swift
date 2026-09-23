import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var session: KernelSession

    var body: some View {
        ScreenScaffold(title: "Settings", systemImage: "gear") {
            MilestoneBanner()

            VStack(alignment: .leading, spacing: 12) {
                Text("Feature Hub")
                    .font(.headline)

                NavigationLink(destination: ModelsScreen(session: session)) {
                    HStack {
                        Label("Models", systemImage: "cpu")
                            .font(.body.weight(.medium))
                        Spacer()
                        if let active = session.activeModelDescriptor {
                            Text(active.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("None selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: ProvidersScreen(session: session)) {
                    HStack {
                        Label("Providers", systemImage: "server.rack")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text(session.providerID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: SkillsScreen(session: session)) {
                    HStack {
                        Label("Skills", systemImage: "puzzlepiece")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(session.moduleIDs.count) Registered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: MemoryScreen()) {
                    HStack {
                        Label("Memory", systemImage: "brain")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("Active Store")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Runtime & System Diagnostics")
                    .font(.headline)

                StatusRow(title: "Agent Lifecycle", value: session.state.lifecycle.rawValue)
                StatusRow(title: "Active Goals", value: "\(session.goals.count)")
                StatusRow(title: "Provider State", value: session.providerLifecycle)
                StatusRow(title: "Storage Contract", value: "ProductPersistenceContainer (M8)")
                StatusRow(title: "Secrets Boundary", value: "Keychain Contract (M0)")
                StatusRow(title: "Target Device", value: "iPhone 12 Pro Max")
            }
        }
    }
}
