import SwiftUI
import PASkills

struct SkillsScreen: View {
    @ObservedObject var session: KernelSession
    @State private var search = ""

    private var filteredSkills: [SkillManifest] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.skillManifests }
        return session.skillManifests.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.id.rawValue.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private let skillIdeas: [SkillIdea] = [
        .init(id: "document-reader", title: "Đọc và tóm tắt tài liệu", group: "Tri thức", detail: "Nhận tệp đã nhập, trích xuất nội dung được hỗ trợ, tóm tắt và giữ nguồn dẫn chiếu."),
        .init(id: "workspace-search", title: "Tìm kiếm workspace", group: "Workspace", detail: "Tìm theo tên và nội dung trong phạm vi được cấp; trả về đường dẫn và đoạn khớp."),
        .init(id: "release-audit", title: "Audit trước phát hành", group: "Kỹ thuật", detail: "Đối chiếu checklist, test, CI và bằng chứng trên commit cụ thể."),
        .init(id: "repo-triage", title: "Phân loại lỗi repo", group: "Kỹ thuật", detail: "Nhóm lỗi theo nguyên nhân gốc, mức ảnh hưởng, bước tái hiện và regression test."),
        .init(id: "memory-curator", title: "Quản lý Memory", group: "Tri thức", detail: "Đề xuất dữ kiện đáng lưu, ghi nguồn và cho phép sửa hoặc quên thông tin."),
        .init(id: "safe-file-transform", title: "Chuyển đổi tệp an toàn", group: "Dữ liệu", detail: "Kiểm tra định dạng và giới hạn trước khi chuyển đổi; không ghi đè âm thầm."),
        .init(id: "meeting-actions", title: "Tách việc từ ghi chú", group: "Công việc", detail: "Trích xuất quyết định, người phụ trách khi được nêu, thời hạn và việc còn mở."),
        .init(id: "provider-diagnostics", title: "Chẩn đoán Provider", group: "Hệ thống", detail: "Phân biệt cấu hình, xác thực, kết nối, HTTP, stream và lỗi runtime mà không lộ secret.")
    ]

    var body: some View {
        ScreenScaffold(title: "Skills", systemImage: "puzzlepiece") {
            GlassPanel {
                HStack {
                    Label("Available Skills", systemImage: "sparkles").font(.headline)
                    Spacer()
                    Text("\(session.skillManifests.count)").font(.title3.bold())
                }
                Text("Danh sách bên dưới chỉ gồm Skill đã được runtime phát hiện. Ý tưởng trong thư viện không được cài hoặc thực thi tự động.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Tìm Skill theo tên, ID hoặc mô tả…", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(11).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No Skills" : "Không tìm thấy Skill",
                        systemImage: "puzzlepiece",
                        description: Text(search.isEmpty ? "Chưa có Skill.md hợp lệ trong Skill store." : "Thử tìm bằng một phần tên, ID hoặc mô tả.")
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredSkills, id: \.id) { skill in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.title3).foregroundStyle(.tint)
                                .frame(width: 38, height: 38)
                                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(skill.name).font(.headline)
                                    Spacer()
                                    Text("\(skill.version)").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(skill.id.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(skill.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    }
                }
                if !search.isEmpty {
                    HStack {
                        Text("\(filteredSkills.count) / \(session.skillManifests.count) Skills").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Xóa tìm kiếm") { search = "" }.font(.caption.weight(.semibold))
                    }
                }
            }

            GlassPanel {
                Label("Skill execution contract", systemImage: "checkmark.shield").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    contractStep("01", "Discover", "Tìm manifest hợp lệ; ID và phiên bản phải rõ ràng.")
                    contractStep("02", "Scope", "Agent.md chỉ được gọi những Skill đã khai báo và tồn tại.")
                    contractStep("03", "Validate", "Kiểm tra input, quyền và điều kiện trước khi chạy.")
                    contractStep("04", "Execute", "Runtime chạy capability; UI không tự giả lập kết quả.")
                    contractStep("05", "Verify", "Đối chiếu output với điều kiện hoàn thành trước khi báo PASS.")
                }
                Text("Nếu thiếu Skill, input mơ hồ hoặc xác minh thất bại, kết quả phải được báo là chưa hoàn tất — không tự suy diễn thành thành công.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Skill idea library").font(.title3.bold())
                        Text("8 mẫu năng lực để phát triển tiếp").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lightbulb").font(.title2).foregroundStyle(.tint)
                }
                GlassPanel {
                    Text("Ý TƯỞNG — CHƯA ĐƯỢC CÀI").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                    ForEach(skillIdeas) { idea in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "plus.square.dashed").foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(LocalizedStringKey(idea.title)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(LocalizedStringKey(idea.group)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(LocalizedStringKey(idea.detail)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }

            GlassPanel {
                Label("Agent scope", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
                Text("Agent.md controls which declared Skills may be selected. Execution remains policy-gated and independently verified. Đổi LLM không nên làm thay đổi quyền hoặc hợp đồng của Skill.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func contractStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.monospaced().bold()).foregroundStyle(.tint).frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SkillIdea: Identifiable {
    let id: String
    let title: String
    let group: String
    let detail: String
}
