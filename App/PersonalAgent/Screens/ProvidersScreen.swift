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
                Divider()
                Text("Agent identity, permissions and verification rules remain fixed when the model changes. Provider supplies inference; Runtime owns execution policy.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Chọn engine theo tác vụ", systemImage: "arrow.left.arrow.right").font(.headline)
                guideRow("Local model", "Ưu tiên riêng tư và ngoại tuyến; phụ thuộc RAM, nhiệt độ, tốc độ và chất lượng.", symbol: "iphone")
                guideRow("Remote provider", "Phù hợp suy luận nặng hơn; cần mạng, credential an toàn và kiểm soát dữ liệu gửi đi.", symbol: "cloud")
                guideRow("Code Engine", "Ưu tiên cho phép tính, parsing, validation và quy tắc cần kết quả xác định.", symbol: "curlybraces")
                Text("Không có model tối ưu cho mọi việc. Đánh giá bằng tác vụ thật, độ chính xác, độ trễ, chi phí và năng lượng.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Chẩn đoán nhanh", systemImage: "stethoscope").font(.headline)
                guideRow("401 / 403", "Kiểm tra credential, quyền model và trạng thái tài khoản; không đưa key vào chat hoặc log.", symbol: "lock")
                guideRow("404 / model not found", "Đối chiếu chính xác model ID và endpoint/base URL.", symbol: "magnifyingglass")
                guideRow("Network / timeout", "Xác minh mạng, TLS và tình trạng dịch vụ; phân biệt timeout với lỗi nội dung.", symbol: "wifi.exclamationmark")
                guideRow("Kết nối được nhưng Chat lỗi", "Lỗi có thể nằm ở request, stream, runtime hoặc UI; lưu lỗi gốc và tái hiện một lượt ngắn.", symbol: "bubble.left.and.bubble.right")
                guideRow("Stream lặp hoặc sai thứ tự", "Kiểm tra thứ tự delta, completion cuối, Stop/cancellation và kết quả của request cũ.", symbol: "arrow.trianglehead.2.clockwise")
                Text("Không ghi API key, Authorization header hoặc nội dung nhạy cảm vào log. Chỉ gửi dữ liệu cần thiết cho remote provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func guideRow(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }


}
