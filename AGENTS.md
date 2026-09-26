# AGENTS.md — PersonalAgent-iOS Working Rules

<!-- TASK-CONTEXT: This file is the default workflow contract for AI workers operating on this repository. Read it before starting architecture, repair, migration, or audit work. -->

## Mission

## Agent Memory Routing — FAST PATH

> **Read order:** `BASELINE.md` → relevant `Documentation/MEMORY.md` → only then `HANDOFF.md` / `AUDIT.md` / `WORK_LOG.md` when needed.
>
> **STOP EARLY:** If BASELINE/MEMORY already answer the task, stop. Do not reconstruct repository state from the full Markdown tree or chat history.
>
> Markdown is a **soft memory protocol**: current/high-value knowledge goes near the top; history may grow below; headings and routing hints are retrieval aids, not rigid parser rules.

## FAST READ — soft guidance

> Read from the top. If the current section answers the task, **STOP EARLY**. Read deeper only when evidence/history/ownership is needed. This is guidance, not a rigid parser contract. Useful data may grow below.


Keep PersonalAgent-iOS structurally coherent, testable, and incrementally evolvable.

## Mandatory Workflow

`inspect -> confirm -> minimal change -> regression test -> full gate -> audit -> record -> handoff`

### 1. Inspect

- Read the relevant Issue/PR.
- Inspect actual repository files and dependency declarations.
- Identify current ownership before proposing a move.
- Read `Documentation/ARCHITECTURE.md`, `Documentation/AUDIT.md`, and `Documentation/HANDOFF.md`.

### 2. Confirm

Classify every finding:
- **CONFIRMED** — repository evidence proves it.
- **NOT CONFIRMED** — evidence does not establish it.
- **DEFERRED** — valid but intentionally postponed.

Never manufacture bugs from architectural preference.

### 3. Minimal Change

- Fix only the confirmed scope.
- Prefer moving code before rewriting it during migration.
- Do not perform unrelated cleanup.
- Do not introduce generic folders without a proven boundary.

### 4. Regression Test

Every behavior change gets regression coverage. Architecture-only moves still require build/test verification.

### 5. Full Gate

Run applicable build, unit tests, dependency/architecture checks, and platform validation. Never call a task complete from a partial test.

### 6. Audit

After implementation, inspect the resulting structure and dependency direction again.

### 7. Record

Update the relevant Markdown in the same task.

<!-- INVARIANT: Code without recorded architectural reasoning is incomplete when the change affects ownership, boundaries, dependencies, migration, or future worker behavior. -->

Record: what changed; why; evidence; confirmed/deferred findings; verification; known limitations; exact next step.

### 8. Handoff

Leave the repository in a state where the next worker can continue without reconstructing the previous task from chat history. Update `Documentation/HANDOFF.md`.

## Architecture Rules

- Kernel = contracts/events/errors/ports; no vendor implementation.
- Runtime = agent execution/orchestration.
- Capabilities = modules/skills/tools.
- Providers = provider/model adapters.
- Memory = agent memory/retrieval semantics.
- Storage = persistence/data boundary.
- Composition = construction and wiring.
- App = presentation; no direct vendor/runtime/storage wiring.
- Tests mirror production ownership.

<!-- INVARIANT: One concept -> one place. One boundary -> one folder. One execution path -> one Runtime. One wiring point -> Composition. -->

## Stop Conditions

Stop and report instead of guessing when ownership is ambiguous, two canonical destinations appear equally valid, migration would require uncovered behavior changes, a test failure indicates a separate defect, or requested architecture conflicts with documented invariants.

## Handoff Template

```markdown
## Task Result

### Completed
- ...

### Confirmed
- ...

### Deferred
- ...

### Verification
- ...

### Next Exact Action
1. ...

### Do Not Redo
- ...
```

<!-- FINAL-CHECK: Before declaring completion, verify that code, tests, documentation, and handoff all describe the same repository state. -->

## Kiểm tra và sửa chữa — Agent Protocol

- Workflow chính: **Kiểm tra và sửa chữa** (.github/workflows/ci.yml).
- Khi nhận báo Run failed / PR run failed, hiểu mặc định là **phải kiểm tra và sửa**, không chỉ báo cáo.
- Luôn xác minh **PR/branch trước**, rồi lấy head SHA hiện tại và workflow run mới nhất. Nếu người dùng chỉ đưa một SHA, coi đó là **tín hiệu để truy tìm run/commit**, không phải lý do để dừng nếu lookup SHA trực tiếp thất bại.
- Nếu lookup SHA không ra PR/commit: **không yêu cầu người dùng gửi link ngay**. Trước tiên search PR đang mở của repo, chọn workstream mới nhất liên quan, rồi lấy latest workflow run/jobs/logs từ head SHA hiện tại.
- Chỉ kết luận không xác định được lỗi sau khi đã thử: PR search → PR info → head SHA → workflow runs → failed job → job logs.
- Đọc log của job đỏ để xác định nguyên nhân **CONFIRMED**; không đoán lỗi.
- Sửa tối thiểu, ưu tiên **một commit cho một logical fix**; không gom nhiều lỗi không liên quan.
- Sau sửa: chờ/check workflow mới, xác nhận Full Gate xanh rồi mới kết luận hoàn tất.
- Nếu workflow chưa chạy xong, trạng thái phải ghi rõ **CHƯA XÁC MINH**.
- **Auto Repair** chạy tự động trên push vào `rearch/**` và có guarded repair loop. Unknown failure vẫn fail-closed; lỗi lặp được ghi nhớ bằng fingerprint/observation count.
- Nếu CI đỏ lặp lại, không tạo vòng sửa mù: đọc job/log mới nhất, xác định regression hoặc nguyên nhân mới, rồi mới sửa.
- Không dùng Jules/Jan prompt làm bước mặc định; agent đang xử lý repo có thể trực tiếp inspect/fix khi connector cho phép.
- Sau mỗi nhóm migration: cập nhật tài liệu/handoff để worker sau đọc được trạng thái mà không cần khôi phục từ chat.
