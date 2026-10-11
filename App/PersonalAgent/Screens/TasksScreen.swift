import SwiftUI
import UIKit

struct TasksScreen: View {
    @ObservedObject var session: KernelSession
    @State private var copiedContentLabel: String? = nil

    private var activeAgentName: String {
        session.agentManifests.first(where: { $0.id == session.selectedAgentID })?.name ?? session.selectedAgentID
    }

    private var taskStateTitle: String {
        if session.isSubmitting { return "Đang thực thi" }
        if session.lastError != nil { return "Cần chú ý" }
        if session.executionResult != nil { return "Có kết quả gần nhất" }
        return "Sẵn sàng nhận việc"
    }

    var body: some View {
        ScreenScaffold(title: "Tasks", systemImage: "checklist") {
            GlassPanel {
                HStack(spacing: 12) {
                    Image(systemName: session.isSubmitting ? "sparkles" : "checklist")
                        .font(.title2).foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(taskStateTitle)).font(.headline)
                        Text(session.executionProgress?.detail ?? "Trạng thái dưới đây phản ánh phiên Agent hiện tại, không phải lịch sử job độc lập.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.isSubmitting { ProgressView() }
                }
                Divider()
                StatusRow(title: "Agent", value: activeAgentName)
                StatusRow(title: "Provider", value: session.providerID)
                StatusRow(title: "Lifecycle", value: session.state.lifecycle.rawValue)
                StatusRow(title: "Skills available", value: "\(session.skillManifests.count)")
                StatusRow(title: "Memory records", value: "\(session.memoryRecords.count)")
                StatusRow(title: "Team mode", value: session.teamModeEnabled ? "Enabled" : "Disabled")
            }

            if let progress = session.executionProgress {
                GlassPanel {
                    Label("Live execution", systemImage: "waveform.path").font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.title).font(.headline)
                            Text(progress.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("Không đóng ứng dụng hoặc đổi Agent giữa một tác vụ đang chạy nếu chưa hiểu tác động. Dùng Stop trong Chat để yêu cầu hủy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let result = session.executionResult {
                GlassPanel {
                    Label("Latest result", systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text(result).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = result
                        copiedContentLabel = "Copied"
                    } label: {
                        Label(copiedContentLabel ?? "Copy result", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    Text("Đầu ra hiển thị không tự chứng minh mọi tác động phụ đã hoàn tất. Kiểm tra tệp, trạng thái và bằng chứng liên quan trước khi dùng kết quả.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error = session.lastError {
                GlassPanel {
                    Label("Execution needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = error
                        copiedContentLabel = "Copied"
                    } label: {
                        Label(copiedContentLabel ?? "Copy error", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    Text("Hãy giữ lại lỗi gốc và bước tái hiện. Tránh chạy lặp lại một thao tác có tác dụng phụ trước khi xác định trạng thái hiện tại.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            GlassPanel {
                Label("Vòng đời của một tác vụ", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                taskStep("01", "Hiểu yêu cầu", "Làm rõ mục tiêu, phạm vi và điều kiện hoàn thành.")
                taskStep("02", "Chọn năng lực", "Runtime chọn Agent/Skill phù hợp; quyền không do LLM tự cấp.")
                taskStep("03", "Thực thi có giới hạn", "Dùng capability được cho phép, ghi nhận lỗi và hỗ trợ hủy.")
                taskStep("04", "Xác minh", "Đọc lại kết quả thực tế, kiểm tra invariant và phát hiện đầu ra rỗng/mâu thuẫn.")
                taskStep("05", "Báo trạng thái trung thực", "Phân biệt hoàn thành, thất bại, bị hủy và chưa đủ bằng chứng.")
            }

            GlassPanel {
                Label("Checklist kết quả đáng tin", systemImage: "checkmark.shield").font(.headline)
                reliabilityItem("Có đầu ra cụ thể", "Tệp, dữ liệu, kết quả hoặc thay đổi quan sát được.")
                reliabilityItem("Có bằng chứng", "Test, read-back, log an toàn hoặc trạng thái sau thực thi.")
                reliabilityItem("Không vượt quyền", "Không đọc/ghi ngoài phạm vi; không tiết lộ credential.")
                reliabilityItem("Có đường phục hồi", "Biết điều gì đã thay đổi và cách rollback khi cần.")
            }

            GlassPanel {
                Label("Giới hạn hiện tại", systemImage: "info.circle").font(.headline)
                Text("Màn hình này hiển thị trạng thái và kết quả gần nhất của phiên, chưa phải hàng đợi tác vụ bền vững hay audit log đầy đủ. Lịch sử job độc lập, retry có idempotency và phục hồi sau khi ứng dụng khởi động lại vẫn cần được nghiệm thu riêng.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func taskStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.monospaced().bold()).foregroundStyle(.tint).frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func reliabilityItem(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle").foregroundStyle(.tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
