import SwiftUI

struct ChatScreen: View {
    @ObservedObject var session: KernelSession
    @ObservedObject var streamPresentation: ChatStreamPresentation

    init(session: KernelSession) {
        self.session = session
        self._streamPresentation = ObservedObject(wrappedValue: session.chatStreamPresentation)
    }
    @State private var message = ""
    @State private var renameText = ""
    @State private var showRename = false
    @State private var showPromptLibrary = false
    @FocusState private var focused: Bool

    private var currentTitle: String { session.conversations.first(where: { $0.id == session.currentConversationID })?.title ?? "Conversation" }
    private var conversationExportText: String {
        session.chatHistory.map { turn in
            let speaker = turn.role == .user ? "You" : "Personal Agent"
            return "\(speaker):\n\(turn.content)"
        }.joined(separator: "\n\n")
    }

    var body: some View {
        ScreenScaffold(title: "Chat", systemImage: "bubble.left.and.bubble.right", scrollable: false) {
            conversationHeader
            agentPicker
            messages
            if let error = session.lastError, !error.isEmpty {
                failureNotice(error)
            }
            composer
        }
        .task {
            await session.prepareActiveModel()
        }
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Conversation name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.renameCurrentConversation(renameText) }
        }
        .sheet(isPresented: $showPromptLibrary) {
            AgentPromptLibrary { prompt in
                message = prompt
                showPromptLibrary = false
                focused = true
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var conversationHeader: some View {
        GlassPanel {
            HStack(spacing: 12) {
                PremiumIconTile(systemImage: "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTitle).font(.headline).lineLimit(1)
                    Text("\(session.chatHistory.count) turns").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button { session.newConversation() } label: { Label("New conversation", systemImage: "plus") }
                    Menu("Response language") {
                        Button("Automatic" + (session.chatResponseLanguage == "auto" ? " ✓" : "")) { session.setChatResponseLanguage("auto") }
                        Button("Tiếng Việt" + (session.chatResponseLanguage == "vi" ? " ✓" : "")) { session.setChatResponseLanguage("vi") }
                        Button("English" + (session.chatResponseLanguage == "en" ? " ✓" : "")) { session.setChatResponseLanguage("en") }
                    }
                    Menu("Độ dài ngữ cảnh · \(session.chatContextTurnLimit) lượt") {
                        ForEach([4, 8, 12, 24, 48], id: \.self) { limit in
                            Button("\(limit) lượt" + (session.chatContextTurnLimit == limit ? " ✓" : "")) {
                                session.setChatContextTurnLimit(limit)
                            }
                        }
                    }
                    if session.canRegenerateLastResponse {
                        Button {
                            Task { await session.regenerateLastResponse() }
                        } label: {
                            Label("Regenerate answer", systemImage: "arrow.clockwise")
                        }
                    }
                    ShareLink(item: conversationExportText) {
                        Label("Export conversation", systemImage: "square.and.arrow.up")
                    }
                    .disabled(session.chatHistory.isEmpty)
                    Button { showPromptLibrary = true } label: { Label("Thư viện tác vụ · 28 mẫu", systemImage: "books.vertical") }
                    Button { renameText = currentTitle; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    if session.conversations.count > 1 {
                        Section("Conversations") {
                            ForEach(session.conversations) { conversation in
                                Button { session.selectConversation(id: conversation.id) } label: {
                                    HStack { Text(conversation.title); if conversation.id == session.currentConversationID { Spacer(); Image(systemName: "checkmark") } }
                                }
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { session.deleteConversation(id: session.currentConversationID) } label: { Label("Delete conversation", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .disabled(session.isSubmitting)
            }
        }
    }

    @ViewBuilder private var agentPicker: some View {
        if !session.agentManifests.isEmpty {
            GlassPanel {
                Menu {
                    ForEach(session.agentManifests, id: \.id) { agent in
                        Button { session.selectAgent(id: agent.id) } label: { HStack { Text(agent.name); if agent.id == session.selectedAgentID { Spacer(); Image(systemName: "checkmark") } } }
                    }
                } label: {
                    HStack(spacing: 10) {
                        PremiumIconTile(systemImage: "person.crop.circle.badge.checkmark")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Agent").font(.caption).foregroundStyle(.secondary)
                            Text(session.agentManifests.first(where: { $0.id == session.selectedAgentID })?.name ?? "Personal Default Agent").font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var messages: some View {
        ChatMessagesPanel(history: session.chatHistory, streamPresentation: streamPresentation, onOpenPromptLibrary: { showPromptLibrary = true })
    }

    private var composer: some View {
        GlassPanel {
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Message your Agent…", text: $message, axis: .vertical).focused($focused).textFieldStyle(.plain).lineLimit(1...5).submitLabel(.send).onSubmit(send)
                if session.isSubmitting {
                    Button(action: session.cancelCurrentGeneration) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 34, height: 34)
                            .background(.red.opacity(0.10), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop response generation")
                    .accessibilityHint("Cancels the current Agent request")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(AgentDesign.accent, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                }
            }
            if session.isSubmitting {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(streamPresentation.streamingResponse.isEmpty ? "Agent is thinking…" : "Generating response…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let metrics = streamPresentation.responseMetrics {
                        Text("~\(metrics.estimatedOutputTokens) tokens · \(metrics.estimatedTokensPerSecond, specifier: "%.1f") tok/s")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else if let metrics = streamPresentation.responseMetrics {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").foregroundStyle(.secondary)
                    Text("Last response · ~\(metrics.estimatedOutputTokens) tokens · \(metrics.estimatedTokensPerSecond, specifier: "%.1f") tok/s")
                    if let ttft = metrics.timeToFirstToken {
                        Text("· first token \(ttft, specifier: "%.2f")s")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    
    private func failureNotice(_ error: String) -> some View {
        GlassPanel {
            Label("Agent could not complete the request", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error)
                .font(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink {
                SettingsScreen(session: session)
            } label: {
                Label("Check provider and model settings", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
    }

    private func send() {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !session.isSubmitting else { return }
        message = ""; focused = false
        Task { await session.submitGoal(value) }
    }
}


private struct ChatMessagesPanel: View {
    let history: [ChatTurn]
    @ObservedObject var streamPresentation: ChatStreamPresentation
    let onOpenPromptLibrary: () -> Void

    var body: some View {
        GlassPanel {
            if history.isEmpty {
                VStack(spacing: 12) {
                    PremiumIconTile(systemImage: "sparkles")
                    Text("Start a conversation").font(.headline)
                    Text("Ask the Agent to explain, plan, create or act.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(action: onOpenPromptLibrary) {
                        Label("Khám phá thư viện tác vụ", systemImage: "books.vertical")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }.frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity).padding(.vertical, 36)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(history) { turn in ChatBubble(turn: turn).id(turn.id) }
                            if !streamPresentation.streamingResponse.isEmpty {
                                StreamingChatBubble(content: streamPresentation.streamingResponse).id("streaming-response")
                            }
                        }.padding(.vertical, 4)
                    }
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .onChange(of: history.count) { _, _ in if let id = history.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } } }
                    .onChange(of: streamPresentation.streamingResponse) { _, value in
                        guard !value.isEmpty else { return }
                        // Streaming text is refreshed in batches; don't animate every batch.
                        proxy.scrollTo("streaming-response", anchor: .bottom)
                    }
                    .onAppear { if let id = history.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
    }
}

private enum PromptCategory: String, CaseIterable, Identifiable {
    case all = "Tất cả", planning = "Kế hoạch", knowledge = "Tri thức", writing = "Sáng tạo", coding = "Lập trình", workspace = "Workspace", agentOS = "AgentOS", review = "Kiểm tra"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .planning: "calendar"
        case .knowledge: "brain"
        case .writing: "pencil.and.outline"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .workspace: "folder"
        case .agentOS: "cpu"
        case .review: "checkmark.shield"
        }
    }
}

private struct AgentPrompt: Identifiable {
    let id: String
    let title: String
    let detail: String
    let category: PromptCategory
    let body: String

    static let catalog: [AgentPrompt] = [
        .init(id:"week",title:"Lập kế hoạch tuần",detail:"Ưu tiên, thời gian, kết quả đo được",category:.planning,body:"Giúp tôi lập kế hoạch tuần. Chia mục tiêu thành việc nhỏ, ước lượng thời gian, nêu ưu tiên và tiêu chí hoàn thành. Hỏi tối đa 3 câu nếu thiếu thông tin."),
        .init(id:"project",title:"Khởi tạo dự án",detail:"Mục tiêu → mốc → rủi ro → bước đầu",category:.planning,body:"Lập kế hoạch dự án cho mục tiêu: [mô tả]. Nêu phạm vi, giả định, mốc bàn giao, rủi ro, việc phụ thuộc và 3 hành động đầu tiên."),
        .init(id:"decision",title:"Ra quyết định",detail:"So sánh lựa chọn theo tiêu chí",category:.planning,body:"So sánh các lựa chọn [A/B/C]. Xác định tiêu chí và trọng số, lợi ích, chi phí, rủi ro và điều kiện khiến khuyến nghị thay đổi. Tách dữ kiện khỏi giả định."),
        .init(id:"daily",title:"Tổng kết ngày",detail:"Kết quả, điểm nghẽn, ngày mai",category:.planning,body:"Dẫn tôi tổng kết ngày: việc đã xong, chưa xong, nguyên nhân, điều học được và 3 ưu tiên ngày mai. Không tự bịa thông tin tôi chưa cung cấp."),
        .init(id:"breakdown",title:"Chia nhỏ công việc",detail:"Checklist có đầu ra rõ ràng",category:.planning,body:"Chia [mục tiêu] thành checklist có thứ tự. Mỗi việc cần đầu ra cụ thể, tiêu chí hoàn thành, phụ thuộc và cách xác minh."),
        .init(id:"learn",title:"Học một chủ đề",detail:"Lộ trình, ví dụ, bài tập",category:.knowledge,body:"Dạy tôi [chủ đề] từ cơ bản đến nâng cao bằng ví dụ thực tế. Kết thúc bằng 5 câu hỏi kiểm tra và một bài tập thực hành có đáp án."),
        .init(id:"compare",title:"So sánh công nghệ",detail:"Trade-off thay vì chạy theo xu hướng",category:.knowledge,body:"So sánh [A] và [B] theo kiến trúc, hiệu năng, chi phí, bảo mật, vận hành và khả năng mở rộng. Nêu trường hợp nên chọn từng phương án."),
        .init(id:"research",title:"Bản nghiên cứu",detail:"Bằng chứng, quan điểm đối lập, giới hạn",category:.knowledge,body:"Lập bản nghiên cứu về [chủ đề]. Tách dữ kiện đã biết, điều chưa chắc chắn, nguồn cần kiểm tra, quan điểm đối lập và kết luận có mức độ tin cậy."),
        .init(id:"glossary",title:"Từ điển dự án",detail:"Thuật ngữ và cách dùng thống nhất",category:.knowledge,body:"Tạo từ điển thuật ngữ cho [dự án]. Mỗi mục có định nghĩa ngắn, ví dụ, thuật ngữ liên quan và quy tắc sử dụng nhất quán."),
        .init(id:"email",title:"Soạn email",detail:"Mục tiêu và lời kêu gọi rõ",category:.writing,body:"Soạn email về [chủ đề] cho [người nhận], mục tiêu [mục tiêu], giọng điệu [giọng điệu]. Viết tiêu đề, nội dung ngắn gọn, yêu cầu và bước tiếp theo."),
        .init(id:"rewrite",title:"Biên tập nội dung",detail:"Giữ ý, tăng độ rõ",category:.writing,body:"Biên tập nội dung sau để rõ và tự nhiên hơn; giữ nguyên dữ kiện, không tự thêm tuyên bố: [dán nội dung]. Sau đó nêu những thay đổi chính."),
        .init(id:"product",title:"Product brief",detail:"Người dùng, vấn đề, giải pháp, đo lường",category:.writing,body:"Viết product brief cho [tính năng]: nhóm người dùng, vấn đề, tình huống sử dụng, giải pháp, phạm vi không làm, tiêu chí thành công, rủi ro và câu hỏi mở."),
        .init(id:"calendar",title:"Lịch nội dung 30 ngày",detail:"Ý tưởng theo kênh và mục tiêu",category:.writing,body:"Lập lịch nội dung 30 ngày cho [chủ đề/đối tượng]. Mỗi mục có chủ đề, định dạng, thông điệp, CTA và cách đo hiệu quả; tránh lặp ý."),
        .init(id:"debug",title:"Điều tra lỗi code",detail:"Tái hiện → giả thuyết → bằng chứng",category:.coding,body:"Điều tra lỗi [mô tả]. Xác định cách tái hiện, bằng chứng cần thu thập, giả thuyết xếp theo xác suất, cách phân biệt và bản sửa tối thiểu kèm regression test."),
        .init(id:"architecture",title:"Rà soát kiến trúc",detail:"Boundary, dependency, invariant",category:.coding,body:"Rà soát kiến trúc [hệ thống]. Tìm ranh giới trách nhiệm, chiều phụ thuộc, điểm ghép chặt, race và lỗ hổng xác minh. Chỉ đề xuất thay đổi khi có bằng chứng."),
        .init(id:"test",title:"Thiết kế test",detail:"Happy path, lỗi, biên, cancellation",category:.coding,body:"Thiết kế test cho [thành phần], gồm happy path, input sai, giới hạn, cancellation, concurrency, persistence và recovery. Ghi invariant được bảo vệ bởi mỗi test."),
        .init(id:"review",title:"Review pull request",detail:"Lỗi thực tế và cách tái hiện",category:.coding,body:"Review diff theo mức nghiêm trọng. Tìm bug, regression, lỗ hổng bảo mật, race và thiếu test. Mỗi phát hiện cần vị trí, điều kiện tái hiện và cách sửa nhỏ nhất."),
        .init(id:"contract",title:"Thiết kế API contract",detail:"Input, output, lỗi, versioning",category:.coding,body:"Thiết kế contract cho [API/module]: input/output, lỗi có kiểu, cancellation, timeout, versioning, quyền hạn và test. Không để implementation phụ thuộc ngược vào UI."),
        .init(id:"workspace",title:"Tổ chức workspace",detail:"Cấu trúc thư mục và quy ước",category:.workspace,body:"Đề xuất cấu trúc workspace cho [dự án], phân loại nguồn, tài liệu, dữ liệu và đầu ra; đặt quy tắc tên, index Markdown và quy trình lưu trữ. Không tự xóa/ghi đè tệp."),
        .init(id:"meeting",title:"Biên bản cuộc họp",detail:"Quyết định và action items",category:.workspace,body:"Chuyển ghi chú sau thành biên bản: nội dung, quyết định đã chốt, việc cần làm, người phụ trách nếu được nêu, thời hạn và câu hỏi mở. Không tự gán chủ sở hữu."),
        .init(id:"agent",title:"Thiết kế Agent.md",detail:"Danh tính cố định, LLM có thể thay",category:.agentOS,body:"Thiết kế Agent.md cho [tên]: identity, mục tiêu, phạm vi, Skills được phép, chính sách dữ liệu, hành động cần xác nhận, quy tắc lỗi và tiêu chí xác minh. Không gắn Agent vào một LLM cụ thể."),
        .init(id:"skill",title:"Thiết kế Skill.md",detail:"Một năng lực, một hợp đồng rõ",category:.agentOS,body:"Thiết kế Skill.md cho [năng lực]: mục đích, input/output schema, preconditions, quyền, bước thực thi, lỗi, invariant và test. Giữ phạm vi nhỏ, không biến Skill thành Agent tổng quát."),
        .init(id:"multi",title:"Phân công nhiều Agent",detail:"Vai trò, phụ thuộc, hợp nhất",category:.agentOS,body:"Chia [mục tiêu] cho nhiều Agent với vai trò riêng. Nêu nhiệm vụ, phụ thuộc, dữ liệu chia sẻ, tiêu chí đầu ra, cách hợp nhất và phát hiện kết quả mâu thuẫn."),
        .init(id:"sandbox",title:"Kiểm thử sandbox",detail:"Path traversal, secret, rollback",category:.agentOS,body:"Lập ma trận kiểm thử sandbox: path traversal, symlink, lệnh sai, giới hạn tài nguyên, dữ liệu nhạy cảm, cancellation, snapshot, rollback và bằng chứng xác minh."),
        .init(id:"release",title:"Checklist phát hành",detail:"CI, bảo mật, thiết bị, phục hồi",category:.review,body:"Tạo checklist phát hành cho [phiên bản]: CI, build thiết bị, migration, bảo mật, crash, hiệu năng, accessibility, dữ liệu cũ, rollback và smoke test. Đánh dấu bằng chứng còn thiếu."),
        .init(id:"security",title:"Audit bảo mật",detail:"Threat model và kiểm soát",category:.review,body:"Threat-model cho [thành phần]: tài sản, ranh giới tin cậy, attacker, đường tấn công, mức ảnh hưởng, phòng vệ và test âm tính. Không kết luận an toàn chỉ vì có guard."),
        .init(id:"verify",title:"Kiểm chứng kết luận",detail:"Dữ kiện, suy luận, giả định",category:.review,body:"Kiểm chứng kết luận [kết luận]. Tách dữ kiện, suy luận, giả định và điều chưa biết; nêu bằng chứng cần có, cách bác bỏ kết luận và mức độ tin cậy."),
        .init(id:"performance",title:"Điều tra hiệu năng",detail:"Đo trước, tối ưu đúng nút thắt",category:.review,body:"Lập kế hoạch đo hiệu năng cho [tác vụ]: metric, cách tái hiện, baseline, profiling, giả thuyết nút thắt và tiêu chí dừng. Không tối ưu chỉ dựa trên cảm giác.")
    ]
}

private struct AgentPromptLibrary: View {
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: PromptCategory = .all

    private var filtered: [AgentPrompt] {
        AgentPrompt.catalog.filter {
            (category == .all || $0.category == category) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
             $0.detail.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Thư viện tác vụ cho Agent").font(.title2.bold())
                    Text("Chọn mẫu để đưa vào ô chat, chỉnh sửa rồi tự quyết định khi gửi. Mẫu không tự chạy công cụ.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Tìm theo tên hoặc nội dung…", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .padding(11).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PromptCategory.allCases) { item in
                                Button { category = item } label: {
                                    Label(item.rawValue, systemImage: item.symbol)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 11).padding(.vertical, 8)
                                        .background(category == item ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Text("\(filtered.count) mẫu tác vụ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !search.isEmpty || category != .all {
                            Button("Xóa bộ lọc") { search = ""; category = .all }.font(.caption.weight(.semibold))
                        }
                    }
                }.padding()
                Divider()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { prompt in
                            Button { onChoose(prompt.body) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: prompt.category.symbol).font(.title3).foregroundStyle(.tint)
                                        .frame(width: 40, height: 40).background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(prompt.title).font(.headline)
                                            Spacer()
                                            Image(systemName: "arrow.down.left").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(prompt.detail).font(.subheadline).foregroundStyle(.secondary)
                                        Text(prompt.body).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.05), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                }
            }
            .navigationTitle("Prompt Library").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}

private struct StreamingChatBubble: View {
    let content: String
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PremiumIconTile(systemImage: "sparkles")
            Text(content)
                .font(.body).textSelection(.enabled).frame(maxWidth: 310, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(AnyShapeStyle(.thinMaterial), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.045), lineWidth: 1))
            Spacer(minLength: 18)
        }
    }
}

private struct ChatBubble: View {
    let turn: ChatTurn
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if turn.role == .assistant {
                PremiumIconTile(systemImage: "sparkles")
                bubble
                Spacer(minLength: 18)
            } else {
                Spacer(minLength: 18)
                bubble
                PremiumIconTile(systemImage: "person.fill", tint: .secondary)
            }
        }
    }
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: 310, alignment: .leading)
            if turn.role == .assistant {
                ShareLink(item: turn.content) {
                    Label("Share answer", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(turn.role == .assistant ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(AgentDesign.accent.opacity(0.11)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.045), lineWidth: 1))
    }
}
