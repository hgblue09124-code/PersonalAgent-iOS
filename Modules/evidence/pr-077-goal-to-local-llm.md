# goal-to-local-llm-bridge
ID
goal-to-local-llm-bridge

PURPOSE
Close the application-layer gap between an accepted goal and real local LLM execution.

WHEN
Chat accepts a goal but orchestration stops at proposed state.

RULE
Trigger the existing M6Orchestrator from KernelSession and route reasoning through the existing DynamicActiveProvider/local GGUF path; empty reasoning fails closed.

VERIFY
PR #77 defines the acceptance call graph and deliberately leaves lifecycle, UI, storage, and M7 execution governance unchanged.

STATUS
CONFIRMED

SOURCE
PR #77 — Agent goal to local LLM execution bridge