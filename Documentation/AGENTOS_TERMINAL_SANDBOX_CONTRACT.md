# AgentOS Terminal Sandbox Contract

Status: CP0 contract baseline  
Scope: PersonalAgent-iOS AgentOS runtime  
Source of truth: `main`

## 1. Purpose

The Terminal Sandbox is a controlled AgentOS workspace/runtime boundary. It gives Chat and Terminal a shared Kernel execution path while keeping mutable AgentOS definitions and data outside native implementation code.

## 2. Layer boundary

```
SwiftUI App
  -> Composition
  -> Runtime
  -> Kernel
  -> AgentOS capabilities
     -> Workspace / Terminal / Skills / Modules / Tools
```

The Terminal is a capability surface, not a second Agent or a second Kernel.

## 3. Workspace root

All mutable AgentOS state is rooted below one sandbox workspace:

```
AgentOS/
  .agent/
  agents/
  skills/
  modules/
  tools/
  workspace/
  memory/
  config/
  logs/
  cache/
```

No workspace API may escape the configured sandbox root.

## 4. Path invariant

Reject absolute paths and traversal that resolves outside the sandbox root, including `..` traversal. Path normalization must happen before authorization and filesystem access.

Workspace APIs must preserve Unicode filenames and treat file contents as opaque bytes/text according to the declared operation.

## 5. Execution invariant

Every future terminal command follows:

```
parse -> authorize -> execute -> result
```

There is no command path that bypasses Kernel authorization or the workspace boundary.

## 6. Markdown boundary

`Agent.md`, `Skill.md`, module definitions, routing/configuration, and compatible AgentOS data are mutable workspace state. They are definitions/data consumed by native runtime contracts; they are not arbitrary native executable code.

Native Kernel/security implementation, SwiftUI implementation, native provider/engine, entitlements, and native frameworks remain IPA-bound.

## 7. Git boundary

Git/GitHub integration is a later checkpoint. CP0 deliberately does not grant terminal commands arbitrary host Git/process access. Future Git operations must use a bounded repository service and the same authorization/transaction model.

## 8. Update boundary

Soft updates may replace compatible AgentOS definitions/data without reinstalling the IPA. Activation must eventually use:

```
download -> stage -> validate -> test -> snapshot -> activate
```

Rollback is mandatory before automatic activation is introduced.

## 9. Acceptance for CP0

CP0 is complete when this contract is committed on `main` and the existing package graph remains unchanged by the contract itself. CI/build gates remain asynchronous evidence and are not a blocker for the next independent implementation task.

## 10. Non-goals

CP0 does not implement:
- filesystem operations
- terminal commands
- terminal UI
- Git/GitHub
- auto-update
- permission/audit runtime

Those are separate logical tasks/checkpoints.
