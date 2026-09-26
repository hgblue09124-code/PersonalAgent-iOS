# gguf-vertical-slice
ID
gguf-vertical-slice

PURPOSE
Define the minimum complete path for native GGUF local inference.

WHEN
Adding real local inference support.

RULE
Keep parsing, model residency, engine lifecycle, streaming, cancellation, thermal/memory governance, and provider adaptation behind PAProvidersLocal.

VERIFY
M8.1 test suite covered lifecycle, residency, streaming, cancellation, thermal/memory governance, security, tool isolation, and adapter bridging.

STATUS
CONFIRMED

SOURCE
PR #34 — llama.cpp GGUF local inference vertical slice