import SwiftUI
import PASecurity

struct ProvidersScreen: View {
    @ObservedObject var session: KernelSession
    @AppStorage("provider.remote.id") private var remoteProvider = "openai"

    private var credentialSaved: Bool {
        (try? KeychainSecretStore().load(account: "provider.api-key.\(remoteProvider)")) != nil
    }

    private var connectionState: String {
        if session.providerLifecycle.lowercased().contains("error") {
            return "Attention"
        }
        if UserDefaults.standard.bool(forKey: "provider.remote.enabled") {
            return credentialSaved ? "Configured" : "Missing API key"
        }
        return "Local / fallback"
    }

    private var providerDisplayName: String {
        switch remoteProvider {
        case "grok": return "Grok"
        case "openai-compatible": return "OpenAI Compatible"
        default: return "OpenAI"
        }
    }

    var body: some View {
        ScreenScaffold(title: "Providers", systemImage: "server.rack") {
            GlassPanel {
                Label("Active provider", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                StatusRow(title: "Provider", value: session.providerID)
                StatusRow(title: "Lifecycle", value: session.providerLifecycle)
                StatusRow(title: "Connection", value: connectionState)
                StatusRow(title: "Execution", value: UserDefaults.standard.string(forKey: "provider.execution.mode") == "remote" ? "Remote" : "Local")
            }

            GlassPanel {
                Label("Remote configuration", systemImage: "key.fill")
                    .font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(providerDisplayName)
                            .font(.headline)
                        Text(credentialSaved ? "API key stored in Keychain" : "No API key stored")
                            .font(.caption)
                            .foregroundStyle(credentialSaved ? .green : .secondary)
                    }
                    Spacer()
                    Image(systemName: credentialSaved ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(credentialSaved ? .green : .orange)
                        .accessibilityLabel(credentialSaved ? "API key configured" : "API key missing")
                }

                NavigationLink {
                    SettingsScreen(session: session)
                } label: {
                    Label("Configure provider", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Secret material stays inside the Keychain boundary and is never rendered in the Agent surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Provider contract", systemImage: "link")
                    .font(.headline)
                Text("Providers are adapters behind the Agent contract. This surface reports configuration without owning execution.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
