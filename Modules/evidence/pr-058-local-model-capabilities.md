# local-model-capabilities
ID
local-model-capabilities

PURPOSE
Expose real local model lifecycle without moving provider/runtime ownership into UI.

WHEN
Settings needs model import, installed-model state, load/unload, or capability visibility.

RULE
Keep local model storage and lifecycle in application/runtime boundaries; route active local completions through DynamicActiveProvider and the existing adapter.

VERIFY
PR #58 added lifecycle/storage wiring plus unit and integration coverage.

STATUS
CONFIRMED

SOURCE
PR #58 — Extend Settings with Real Local Model Capabilities