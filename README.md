# PersonalAgent — Trợ lý AI cá nhân trên iPhone

**PersonalAgent** hướng tới một hệ điều hành tác nhân cá nhân (*Personal Agent OS*): không chỉ trò chuyện, mà còn có thể sử dụng kỹ năng và công cụ để thực hiện công việc, quản lý tri thức cá nhân, kiểm tra kết quả và phục hồi khi có lỗi.

Ứng dụng được phát triển theo hướng **local-first, bảo mật, có thể mở rộng và tối ưu chi phí**. Định hướng là tận dụng năng lực xử lý ngay trên iPhone khi phù hợp, đồng thời dùng model qua provider cho những tác vụ cần suy luận mạnh hơn.

> **Trạng thái:** đang phát triển và hoàn thiện alpha/beta. Kiến trúc nền và nhiều capability đã có trong mã nguồn, nhưng không phải mọi luồng sản phẩm đều đã được nghiệm thu end-to-end trên thiết bị thật. Vui lòng xem các mục trạng thái bên dưới; không coi tính năng đang phát triển là đã sẵn sàng cho production.

## Tầm nhìn sản phẩm

PersonalAgent hướng tới một nơi thống nhất để người dùng:

- **Giao việc bằng hội thoại:** mô tả mục tiêu tự nhiên, theo dõi tiến trình, xem kết quả và lỗi.
- **Kết hợp nhiều nguồn trí tuệ:** xử lý bằng Swift/rule khi có thể, model nhỏ trên thiết bị cho tác vụ phù hợp, và model từ xa cho việc khó.
- **Dùng Skill và công cụ:** tái sử dụng quy trình có ranh giới rõ ràng thay vì chỉ đưa ra hướng dẫn bằng văn bản.
- **Lưu giữ ngữ cảnh:** quản lý lịch sử hội thoại, Memory và dữ liệu workspace theo các phạm vi riêng biệt.
- **Quản lý dữ liệu của mình:** làm việc với tệp và Markdown, đồng bộ qua GitHub khi được cấu hình, phát hiện xung đột và hướng tới phục hồi an toàn.
- **Kiểm chứng trước khi báo hoàn thành:** đối chiếu kết quả thực tế; không đồng nhất việc công cụ chạy xong với việc mục tiêu đã đạt.

## Các khu vực chính

| Khu vực | Mục tiêu |
| --- | --- |
| Chat & Provider | Gửi yêu cầu qua provider đã chọn và nhận phản hồi; quản lý cấu hình, trạng thái và lỗi kết nối. |
| Local LLM | Hỗ trợ mô hình GGUF tương thích trên thiết bị, tùy model và giới hạn phần cứng. |
| Agent Runtime | Điều phối phiên, trạng thái, kế hoạch và việc thực thi capability. |
| Skills, Modules & Tools | Đóng gói năng lực có hợp đồng đầu vào/đầu ra và giới hạn quyền. |
| Memory | Lưu và truy xuất thông tin được chọn để dùng lại khi phù hợp; không coi toàn bộ lịch sử chat là Memory. |
| Workspace & Terminal Sandbox | Hướng tới thao tác dữ liệu trong phạm vi cho phép, có kiểm tra và phục hồi. |
| GitHub Sync | Hướng tới đồng bộ có kiểm soát, xử lý xung đột và loại trừ dữ liệu nhạy cảm hoặc không được hỗ trợ. |

Danh sách trên mô tả phạm vi sản phẩm; việc một khu vực có giao diện hoặc thành phần nền **không đồng nghĩa** toàn bộ quy trình đã hoàn thiện. Các tính năng cần được xác minh bằng test, CI và nghiệm thu thiết bị tương ứng.

## Nguyên tắc kỹ thuật

- **Local-first khi hợp lý:** ưu tiên xử lý trên thiết bị nếu đáp ứng chất lượng, hiệu năng và mức tiêu thụ năng lượng.
- **Provider-agnostic:** tách hợp đồng model khỏi nhà cung cấp cụ thể.
- **Tối ưu chi phí theo độ khó:** dùng quy tắc và model nhỏ cho việc phù hợp; chỉ nâng cấp lên model mạnh khi cần. Hiệu quả phải được đo trên tác vụ thực tế.
- **Bảo mật theo ranh giới:** thông tin xác thực không được đưa vào mã nguồn, lịch sử chat hay log; công cụ chỉ được thực hiện hành động trong phạm vi được cấp.
- **Có thể kiểm chứng và phục hồi:** đầu ra lỗi, mơ hồ hoặc chưa xác minh không được coi là thành công.
- **Kiến trúc theo capability:** Kernel, Runtime, Skill, Module, Storage và Provider có trách nhiệm riêng; không gom toàn bộ logic vào UI.
- **Sửa đúng nguyên nhân:** giữ nền tảng đang hoạt động; tránh viết lại kiến trúc nếu chưa có bằng chứng kỹ thuật.

## Trạng thái phát triển

Nền tảng hợp đồng, SwiftUI, Kernel/Runtime, Provider, local model, persistence và các capability Memory/Skill/Tool/Module đã có trong mã nguồn. Trạng thái **công việc còn lại** được quản lý duy nhất trong mục [Backlog tập trung](#backlog-tập-trung--nguồn-trạng-thái-duy-nhất) bên dưới; phần này không duy trì checklist trùng lặp.

Thành phần nền có trong source không đồng nghĩa luồng sản phẩm đã được nghiệm thu. CI và nghiệm thu thiết bị được đánh giá theo commit cụ thể; chỉ đánh dấu hoàn thành khi có bằng chứng tương ứng.

## Backlog tập trung — nguồn trạng thái duy nhất

Từ ngày 10/10/2026, dùng checklist này làm nơi theo dõi công việc còn lại; không cần duy trì nhiều issue/PR cũ làm bảng tiến độ song song. **Đóng issue/PR cũ chỉ là dọn cách theo dõi, không có nghĩa các mục chưa tick đã hoàn thành.** Chỉ đánh dấu `[x]` khi có bằng chứng code/test/CI phù hợp; nghiệm thu thiết bị phải có kết quả thực tế.

### Ưu tiên P0 — ổn định sản phẩm
- [ ] **Chat crash / Settings lag (phát hiện 11/10/2026):** PR [#325](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/325) giảm lag một phần nhưng crash vẫn tái hiện theo phản hồi người dùng. Audit source ngày 11/10 xác nhận một đường invalidation UI không cần thiết: `streamingResponse` và `responseMetrics` được publish từ `KernelSession`, đối tượng mà cả Chat lẫn Settings cùng observe. PR này tách stream presentation thành observable riêng để Settings không redraw theo từng batch token; đây là nguyên nhân gây redraw có thật trong code, nhưng mức cải thiện và nguyên nhân crash vẫn cần xác minh trên iPhone. PR [#330](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/330) đã merge tại `6348746`; M3 và Apple Native Build & Unsigned IPA đều PASS trên PR head `435caf6` ([M3](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38115199689), [Apple build](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38115199617)). Bản sửa chuyển witness đồng bộ `LLMProvider.stream` sang `nonisolated` rồi hop vào actor, giữ nguyên HTTP Provider/request/SSE parsing. Đây là sửa lỗi ở cấp source, **chưa phải xác nhận nguyên nhân cuối cùng**: mục vẫn mở đến khi smoke test iPhone xác nhận Chat không crash qua nhiều lượt, Settings phản hồi tốt, stream đúng thứ tự và Stop không để lại tác vụ/nội dung cũ.
- [ ] **Provider → Chat end-to-end:** phần streaming thật đã được nối xuyên suốt HTTP provider → reasoning/runtime → Chat UI; có delta tăng dần, Stop/cancellation, giữ thứ tự delta, xử lý stream rỗng và từ chối completion cuối mâu thuẫn với nội dung đã phát. Reasoning dùng giới hạn tối đa 768 output tokens. Có conditional live test cho completion và SSE của OpenRouter `openrouter/free` khi cung cấp `OPENROUTER_API_KEY`; thiếu secret thì live test phải được báo *skipped*, không tính là PASS. M3 và Apple Native Build & Unsigned IPA đã PASS cho PR #316 tại commit `15a37a8` ([M3](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38105057695), [Apple build](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38105057731)). Còn mở: xác minh request live thành công, credential flow an toàn và nghiệm thu trên iPhone; tốc độ token hiện là ước lượng, không phải usage/tokenizer chính thức của provider.
- [ ] **History, Memory, Skills và Agent Runtime:** M8 integration tests kiểm tra memory persistence/context retrieval và đường Chat → Skill → verified result; PR scope Skills buộc mọi Skill khai báo phải tồn tại trước khi chọn. Chế độ Team chạy tuần tự các Skill phù hợp trên nhiều Agent.md, giữ scope/policy/verification từng Agent; khi không có Skill phù hợp, Chat quay về runtime chính. Còn mở: CI, nghiệm thu nhiều profile cùng mục tiêu, lịch sử Chat và kết quả runtime end-to-end.
- [ ] **GGUF trên iPhone 12 Pro Max:** import file thật, kiểm tra header/metadata, load → generate → stream → cancel → unload, phục hồi sau lỗi và đo tốc độ/nhiệt độ. Không coi fixture hoặc CI là nghiệm thu thiết bị.
  - UI tải dev model hiện dùng chỉ báo hoạt động không xác định trong lúc tải và xác minh checksum; không hiển thị phần trăm giả khi chưa có callback tiến độ truyền thực. Việc import/load/generate GGUF trên iPhone vẫn cần nghiệm thu thiết bị.
- [ ] **Bảo mật dữ liệu:** giữ credential trong Keychain; không log secret; chặn đường dẫn/nội dung nhạy cảm nhất quán ở UI, runtime, storage và sync.
  - Workspace và GitHub Sync kiểm tra protected paths, secret-like content, symlink alias, đường dẫn Windows-style và nguồn append/copy/move; sync phải quét toàn bộ blob tải về trước khi ghi workspace. PR #309 đã có M3 + Apple Native Build & Unsigned IPA PASS trên `7eadd1d`. Các gate đó chỉ xác nhận commit được chạy, không chứng minh toàn bộ bảo mật đã hoàn tất. Còn mở: audit xuyên suốt UI/runtime/sync, credential trong Keychain và nghiệm thu trên thiết bị. Không suy rộng CI của commit cũ sang các commit mới hơn.

### Ưu tiên P1 — AgentOS workspace
- [ ] **Storage:** duyệt, tìm kiếm, đọc, sửa và xác minh dữ liệu persistent qua API có ranh giới rõ; từ chối path traversal, secret và thao tác ngoài workspace.
- [ ] **Terminal Sandbox + GitHub Sync:** [PR #326](https://github.com/hgblue09124-code/personalagent-ios/pull/326) bổ sung preview không áp dụng thay đổi; [#324](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/324) nêu path conflict; [#327](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/327) rollback local apply khi thất bại; [#328](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/328) giữ executable mode; [#329](https://github.com/hgblue09124-code/PersonalAgent-iOS/pull/329) báo commit và các đường dẫn upload/download/delete sau `sync now`. Các PR đã merge; vẫn chưa nghiệm thu recovery và round-trip sync trên iPhone.
  - Đã có lệnh khám phá Skill `skill list [query]` ở runtime và `skills list [query]` trong Terminal iPhone (lọc manifest đã cache theo ID/tên/mô tả). Đây mới là một phần của Terminal; tích hợp đầy đủ Terminal ↔ Workspace ↔ GitHub Sync, conflict và rollback vẫn chưa nghiệm thu.
- [x] **Kiến trúc GGUF:** tách parser định dạng dùng chung khỏi provider/storage; giữ dependency direction một chiều và có test architecture/import-boundary. Bằng chứng: [commit `7eeb7c7`](https://github.com/hgblue09124-code/PersonalAgent-iOS/commit/7eeb7c71650b193b1ca42d935f81f7ac23b8ab51), [M3 PASS](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38052535715), [Apple Native Build & Unsigned IPA PASS](https://github.com/hgblue09124-code/PersonalAgent-iOS/actions/runs/38052535719).

### Ưu tiên P2 — chất lượng phát hành
- [ ] Giữ M3, architecture/import-boundary, package tests và Apple Native Build & Unsigned IPA xanh trên commit cuối cùng.
- [ ] Chạy regression test cho từng sửa lỗi; một tác vụ logic = một commit logic. Fixture kiểm thử dùng thư mục tạm có UUID thực để tránh va chạm khi chạy song song.
- [ ] Hoàn tất smoke test trên thiết bị thật và ghi lại model, thiết bị/iOS, bước thử, kết quả, lỗi còn lại trước khi tuyên bố beta/production-ready.

### Quy tắc cập nhật trạng thái
1. Đây là backlog sản phẩm tập trung; các mục chưa tick vẫn là việc cần làm dù issue/PR cũ đã đóng.
2. Mỗi mục chỉ được tick khi có link commit/PR, test và CI tương ứng; mục thiết bị cần bằng chứng kiểm thử thực tế.
3. Khi bắt đầu việc mới, chọn một mục chưa tick, thực hiện thay đổi tối thiểu có kiểm thử, cập nhật README sau commit và xác minh gate.
4. Không tạo lại issue/PR chỉ để sao chép checklist; chỉ mở lại khi cần thảo luận hoặc review code cụ thể.

## Nền tảng và phát triển

- **Nền tảng:** iOS, Swift, SwiftUI.
- **Thiết bị mục tiêu kiểm thử:** iPhone 12 Pro Max.
- **Package tests:** chạy `swift test` trong môi trường hỗ trợ Swift 6.
- **Ứng dụng iOS:** mở `PersonalAgent.xcodeproj` bằng Xcode tương thích và chọn thiết bị/mô phỏng phù hợp.

Trước khi phát hành, cần xác minh build iOS, các workflow CI bắt buộc, bảo mật credential, khả năng phục hồi sau lỗi và hành vi trên thiết bị thật.

## Nguyên tắc nghiệm thu

1. Một tác vụ logic tương ứng một commit logic.
2. Mỗi sửa lỗi cần có kiểm thử hồi quy phù hợp.
3. Không đưa API key, secret hoặc tệp model lớn vào Git.
4. Không tuyên bố thành công chỉ vì executor trả về thành công; phải kiểm tra kết quả.
5. CI xanh là điều kiện cần, không thay thế nghiệm thu chức năng trên iPhone.

## Định hướng tiếp theo

Ưu tiên kết nối các capability hiện có thành những luồng sử dụng thật; sửa lỗi gốc và cải thiện độ ổn định trước khi mở rộng số lượng tính năng. Sau đó tối ưu định tuyến model, chi phí, độ trễ và nhiệt độ trên thiết bị dựa trên số liệu đo được.

---

PersonalAgent đang được phát triển. Các tính năng, kiến trúc và mốc phát hành có thể thay đổi khi kiểm thử cho thấy cần điều chỉnh.
