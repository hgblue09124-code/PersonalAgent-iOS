# native-agent-experience
ID
native-agent-experience

PURPOSE
Make the Agent UI user-facing instead of exposing permanent technical milestone state.

WHEN
The product has a working execution backend but the primary UX is still infrastructure-oriented.

RULE
Use Agent-first task presentation, progressive disclosure, and native Models/Providers/Skills/Settings surfaces while keeping runtime/provider/local-model/storage boundaries intact.

VERIFY
PR #81 records the UI scope and explicitly forbids direct llama.cpp/provider/storage access from UI.

STATUS
CONFIRMED

SOURCE
PR #81 — BIG native Agent experience