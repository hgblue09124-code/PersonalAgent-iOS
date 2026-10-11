# PersonalAgent

**PersonalAgent** là ứng dụng trợ lý AI cá nhân dành cho iPhone, được phát triển theo hướng *local-first*, có khả năng mở rộng và ưu tiên quyền kiểm soát dữ liệu của người dùng. Mục tiêu dài hạn là kết hợp hội thoại, Agent, Skills, công cụ, bộ nhớ và workspace trong một môi trường thống nhất.

> **Trạng thái dự án:** đang phát triển. README này mô tả sản phẩm, kiến trúc và cách phát triển; không phải bảng tiến độ. Sự hiện diện của giao diện hoặc thành phần trong mã nguồn không bảo đảm toàn bộ luồng đã hoạt động end-to-end. Hãy dựa vào kiểm thử, CI của commit cụ thể và thử nghiệm trên thiết bị để đánh giá mức độ sẵn sàng.

- **Nền tảng:** iOS
- **Công nghệ chính:** Swift, SwiftUI
- **Thiết bị kiểm thử mục tiêu:** iPhone 12 Pro Max
- **Ngôn ngữ tài liệu:** tiếng Việt; giữ nguyên tên API, framework và thuật ngữ tiếng Anh khi cần chính xác.

## Mục tiêu thiết kế

- **Quyền kiểm soát của người dùng:** dữ liệu, cấu hình và hành động của Agent cần có ranh giới rõ ràng.
- **Local-first khi phù hợp:** ưu tiên xử lý trên thiết bị nếu chất lượng, hiệu năng và mức tiêu thụ năng lượng đáp ứng yêu cầu.
- **Linh hoạt về mô hình:** tách logic ứng dụng khỏi nhà cung cấp mô hình; chọn xử lý cục bộ hoặc từ xa theo tác vụ.
- **Thực thi có giới hạn:** Agent chỉ được gọi những capability runtime cho phép; nội dung do mô hình sinh ra không tự nó cấp quyền thực thi.
- **Kết quả có thể kiểm chứng:** phân biệt đầu ra do mô hình tạo, kết quả công cụ trả về và kết quả đã được xác minh.
- **Kiến trúc theo trách nhiệm:** UI, Kernel, Runtime, Skills, Modules, Providers và Storage không nên phụ thuộc chéo tùy tiện.
- **Sửa lỗi dựa trên bằng chứng:** ưu tiên xác định nguyên nhân gốc, thay đổi tối thiểu và kiểm thử hồi quy thay vì viết lại hệ thống không cần thiết.

## Các thành phần của sản phẩm

| Thành phần | Vai trò |
| --- | --- |
| **Chat** | Giao diện hội thoại và trình bày trạng thái, nội dung phản hồi. |
| **Providers** | Kết nối mô hình từ xa thông qua các giao diện provider được hỗ trợ. |
| **Local LLM** | Hỗ trợ hướng chạy mô hình cục bộ, bao gồm GGUF tương thích với runtime và phần cứng. |
| **Kernel & Agent Runtime** | Điều phối phiên và luồng xử lý của Agent. |
| **Agents & Skills** | Mô tả vai trò và quy trình có thể tái sử dụng; quyền thực thi phải được runtime kiểm tra riêng. |
| **Modules & Tools** | Đóng gói chức năng qua các ranh giới và hợp đồng xác định. |
| **Memory & History** | Hỗ trợ lưu giữ ngữ cảnh và lịch sử theo cơ chế mà ứng dụng triển khai. |
| **Workspace & Terminal Sandbox** | Hướng làm việc với dữ liệu và thao tác trong phạm vi được cho phép. |
| **GitHub Sync** | Hỗ trợ quy trình đồng bộ workspace theo những khả năng được triển khai. |
| **Import** | Nhận một số định dạng tệp có hỗ trợ; loại tệp và nội dung vẫn phải được xác thực. |

Bảng trên mô tả các khu vực kiến trúc, không phải cam kết rằng mọi tính năng đã hoàn thiện. Mức hỗ trợ cụ thể có thể khác nhau giữa từng provider, mô hình, định dạng tệp và thiết bị. Không nên coi một mục giao diện, manifest, hướng dẫn hoặc mock test là bằng chứng đủ cho khả năng thực thi thật.

## Kiến trúc ở mức khái quát

Luồng xử lý dự kiến:

`Chat UI → Kernel / Agent Runtime → Capability được cho phép → Kết quả thực thi → Xác minh → UI`

Provider/model cung cấp năng lực suy luận; không nên là nguồn có thẩm quyền duy nhất quyết định quyền truy cập, đường dẫn tệp, thao tác được phép hoặc trạng thái thành công. Các thao tác có tác động cần được giới hạn theo scope, xác thực đầu vào, xử lý lỗi và ghi nhận kết quả phù hợp.

Đây là mô hình trách nhiệm ở mức khái quát. Chi tiết triển khai thực tế cần được đối chiếu với source code và test hiện hành.

## Bảo mật và quyền riêng tư

- Không commit API key, token, thông tin cá nhân nhạy cảm hoặc tệp mô hình lớn vào repository.
- Bí mật cần được lưu trong cơ chế lưu trữ an toàn của nền tảng; không đưa secret vào log, prompt hoặc thông báo lỗi.
- Xác thực dữ liệu nhập, đường dẫn, định dạng và nội dung tệp trước khi sử dụng.
- Từ chối thao tác vượt workspace, scope hoặc quyền đã cấp; không coi chỉ dẫn trong prompt/Skill là quyền hệ thống.
- Các luồng đọc, ghi, import và đồng bộ cần xử lý nhất quán đường dẫn nguy hiểm, dữ liệu nhạy cảm, lỗi một phần và xung đột.
- Khi chưa thể xác minh an toàn hoặc tính toàn vẹn, phải báo lỗi/trạng thái chưa xác minh thay vì báo thành công.

Đây là các yêu cầu thiết kế, không phải tuyên bố rằng toàn bộ kiểm soát bảo mật đã được kiểm toán hoặc chứng minh hoàn chỉnh.

## Yêu cầu phát triển

- macOS và phiên bản Xcode tương thích với cấu hình dự án iOS.
- Swift toolchain tương thích với cấu hình package và các dependency đang sử dụng.
- iPhone hoặc Simulator phù hợp để kiểm thử các luồng dành riêng cho iOS.
- Với tính năng cần model hoặc dịch vụ từ xa, cấu hình credential hợp lệ theo hướng dẫn của provider tương ứng.

Phiên bản công cụ chính xác cần được xác định từ cấu hình dự án và workflow CI hiện hành; không nên suy ra chỉ từ tài liệu này.

## Build và kiểm thử

### Kiểm thử Swift Package

Từ thư mục package có Package.swift, chạy:

```sh
swift test
```

Lệnh này chỉ chạy được trong môi trường đáp ứng toolchain và dependency của package. Kết quả package test không thay thế build ứng dụng iOS hoặc thử nghiệm trên thiết bị thật.

### Build ứng dụng iOS

Mở PersonalAgent.xcodeproj bằng phiên bản Xcode tương thích, chọn scheme và thiết bị đích được cấu hình trong dự án, sau đó build/run. Scheme và cấu hình ký có thể thay đổi theo môi trường.

### Kiểm tra trước khi phát hành

1. Chạy các workflow CI bắt buộc trên đúng commit dự kiến phát hành.
2. Kiểm thử hồi quy cho hành vi đã sửa, bao gồm đường lỗi và huỷ tác vụ khi có liên quan.
3. Kiểm tra cấu hình và xử lý credential; không dùng secret thật trong log hoặc fixture.
4. Với local model, provider streaming, import, terminal và sync, kiểm tra luồng thực tế thay vì chỉ kiểm tra giao diện.
5. Thử trên thiết bị thật đối với các hành vi phụ thuộc iOS, bộ nhớ, hiệu năng, nhiệt độ hoặc filesystem.
6. Ghi rõ thiết bị, phiên bản iOS, cấu hình, các bước tái hiện và kết quả khi báo lỗi.

CI xanh là điều kiện cần, không phải bằng chứng duy nhất rằng ứng dụng đã sẵn sàng cho production.

## Đóng góp

Các đóng góp nên tập trung vào một thay đổi logic rõ ràng, kèm kiểm thử hồi quy tương ứng và mô tả bằng chứng xác minh. Trước khi thay đổi kiến trúc, hãy đọc các hợp đồng và ranh giới hiện có, tìm nguyên nhân gốc, ưu tiên tái sử dụng giải pháp đã được kiểm chứng, đồng thời giữ nguyên giấy phép của mã nguồn bên thứ ba.

Pull request nên nêu:
- Vấn đề và nguyên nhân gốc đã xác minh.
- Phạm vi thay đổi và các bất biến được giữ nguyên.
- Kiểm thử đã chạy, kết quả CI và phần chưa được xác minh.
- Ảnh hưởng bảo mật, dữ liệu hoặc khả năng tương thích nếu có.

Theo dõi công việc, thảo luận và kế hoạch phát hành tại [GitHub Issues](https://github.com/hgblue09124-code/PersonalAgent-iOS/issues) và [Pull Requests](https://github.com/hgblue09124-code/PersonalAgent-iOS/pulls), thay vì biến README thành backlog trùng lặp.

## Báo lỗi

Khi mở issue, hãy cung cấp phiên bản/commit, thiết bị và phiên bản iOS, các bước tái hiện, kết quả mong đợi, kết quả thực tế và log đã loại bỏ thông tin nhạy cảm. Không đính kèm API key, token, dữ liệu riêng tư hoặc tệp model có bản quyền nếu không có quyền chia sẻ.

## Giấy phép

Hãy tham khảo tệp giấy phép được phân phối cùng repository. Nếu repository chưa có giấy phép áp dụng rõ ràng, không nên mặc định rằng mã nguồn được phép sử dụng, sửa đổi hoặc phân phối lại.

---

PersonalAgent là dự án đang phát triển. Phạm vi tính năng và mức độ sẵn sàng cần được đánh giá từ mã nguồn, kiểm thử và bằng chứng thực tế tại thời điểm sử dụng.
