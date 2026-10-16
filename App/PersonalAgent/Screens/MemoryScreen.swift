import SwiftUI
import PAComposition

struct MemoryScreen: View {
    @Environment(\.kernelSession) private var session
    @State private var draft = ""
    @State private var draftKind = "fact"
    @State private var search = ""
    @State private var appliedSearch = ""
    @State private var selectedKind = "all"
    @State private var showClearConfirmation = false
    @State private var isSavingMemory = false
    @State private var memorySaveStatus: String?

    // Keep choices aligned with the kinds included in contextual memory retrieval.
    private let availableKinds = ["fact", "preference", "context", "instruction", "semantic"]

    private var filteredMemories: [MemorySnapshotItem] {
        guard let session else { return [] }
        return session.memoryRecords.filter { record in
            (selectedKind == "all" || record.kind.caseInsensitiveCompare(selectedKind) == .orderedSame) &&
            (appliedSearch.isEmpty || record.content.localizedCaseInsensitiveContains(appliedSearch) ||
             record.kind.localizedCaseInsensitiveContains(appliedSearch))
        }
    }

    var body: some View {
        ScreenScaffold(title: "Memory", systemImage: "brain") {
            GlassPanel {
                HStack(spacing: 12) {
                    Image(systemName: "brain").font(.title2).foregroundStyle(.tint)
                        .frame(width: 42, height: 42)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Personal Memory").font(.headline)
                        Text("Lưu có chọn lọc, truy xuất theo ngữ cảnh").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(session?.memoryRecords.count ?? 0)")
                        .font(.title2.bold().monospacedDigit())
                }
                Text("Memory là tri thức được chọn để dùng lại, không phải bản sao của toàn bộ lịch sử chat. Anh có thể xem, tìm kiếm, thêm hoặc quên từng mục.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            GlassPanel {
                Label("Các lớp Memory", systemImage: "square.stack.3d.up").font(.headline)
                memoryKind("Fact", "Dữ kiện ổn định cần nhớ lại.")
                memoryKind("Preference", "Cách làm việc hoặc lựa chọn người dùng đã nêu.")
                memoryKind("Context", "Bối cảnh dự án có thể thay đổi theo thời gian.")
                memoryKind("Instruction", "Quy tắc làm việc được yêu cầu rõ ràng.")
                memoryKind("Semantic", "Khái niệm và thông tin có ích khi truy xuất.")
                Text("Không lưu mật khẩu, API key, mã khôi phục hoặc thông tin nhạy cảm vào Memory.")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            if let session {
                GlassPanel {
                    HStack {
                        Label("Stored memories", systemImage: "list.bullet.rectangle").font(.headline)
                        Spacer()
                        Text("\(filteredMemories.count) / \(session.memoryRecords.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Tìm trong Memory…", text: $search)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(10).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Picker("Loại", selection: $selectedKind) {
                        Text("Tất cả").tag("all")
                        ForEach(availableKinds, id: \.self) { kind in
                            Text(LocalizedStringKey(kind.capitalized)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    if filteredMemories.isEmpty {
                        ContentUnavailableView(
                            session.memoryRecords.isEmpty ? "Memory đang trống" : "Không tìm thấy mục phù hợp",
                            systemImage: "brain",
                            description: Text(session.memoryRecords.isEmpty
                                ? "Thêm một dữ kiện hoặc sở thích hữu ích bên dưới."
                                : "Thử từ khóa khác hoặc chọn loại Tất cả.")
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredMemories) { record in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(record.kind.capitalized))
                                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    Text(record.content).font(.subheadline).textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) {
                                    Task { await session.forgetMemory(id: record.id) }
                                } label: {
                                    Image(systemName: "trash").font(.caption.weight(.bold))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Forget memory")
                            }
                            .padding(.vertical, 5)
                            Divider().opacity(0.45)
                        }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Thêm Memory", systemImage: "plus.circle").font(.headline)
                        Picker("Remember as", selection: $draftKind) {
                            ForEach(availableKinds, id: \.self) { kind in
                                Text(kind.capitalized).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField("Ví dụ: Tôi thích câu trả lời ngắn, có checklist…", text: $draft, axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(2...5)
                            Button {
                                Task { await saveMemory(using: session) }
                            } label: {
                                if isSavingMemory { ProgressView().controlSize(.small) } else { Text("Lưu") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSavingMemory || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if let memorySaveStatus {
                        Text(memorySaveStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Divider()
                    Button(role: .destructive) { showClearConfirmation = true } label: {
                        Label("Xóa toàn bộ Memory…", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task(id: search) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            appliedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .confirmationDialog("Xóa toàn bộ Memory?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Xóa toàn bộ", role: .destructive) {
                Task { await session?.clearMemory() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Thao tác này xóa các mục Memory đã lưu. Hãy dùng xóa từng mục nếu chỉ muốn quên một thông tin.")
        }
    }

    @MainActor
    private func saveMemory(using session: KernelSession) async {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSavingMemory else { return }
        isSavingMemory = true
        memorySaveStatus = "Đang lưu Memory…"
        let kind = draftKind
        await session.remember(value, kind: kind)
        isSavingMemory = false
        let persisted = session.memoryRecords.contains { $0.content == value && $0.kind.caseInsensitiveCompare(kind) == .orderedSame }
        if persisted {
            draft = ""
            memorySaveStatus = "Đã lưu Memory"
        } else {
            memorySaveStatus = "Chưa xác minh được Memory đã lưu. Đã giữ bản nháp."
        }
    }

    private func memoryKind(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.tint).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
