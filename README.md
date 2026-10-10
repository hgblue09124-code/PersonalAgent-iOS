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

- [x] Nền tảng hợp đồng và ranh giới module trong Swift package.
- [x] Khung ứng dụng SwiftUI và các boundary cho session, Kernel, Provider, local model, persistence và device capability.
- [x] Thành phần nền cho Memory, Skill/Tool/Module và vòng đời thực thi có lưu trạng thái.
- [ ] Hoàn thiện và xác minh end-to-end các luồng Provider, Chat, lịch sử, Memory và Skill.
- [ ] Xác minh import, nạp và chạy GGUF ổn định trên iPhone mục tiêu.
- [ ] Hoàn thiện Workspace/Terminal Sandbox, GitHub sync hai chiều, xung đột và rollback.
- [ ] Hoàn tất các cổng CI/build phát hành và nghiệm thu trên thiết bị thật.

Các mục đã đánh dấu hoàn thành nói về thành phần nền trong mã nguồn, không phải chứng nhận rằng toàn bộ sản phẩm đã đạt chuẩn phát hành. Trạng thái CI và nghiệm thu có thể thay đổi theo từng commit.

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
