# dev-model-download
ID
dev-model-download

PURPOSE
Provide a bounded development path for installing a lightweight public GGUF model.

WHEN
Developers need a reproducible small model for iPhone testing.

RULE
Keep the convenience path dev-only; verify download size and SHA-256 before using the existing model storage import.

VERIFY
PR #73 specifies a 350 MB hard limit and SHA-256 verification; failed download/hash/size never installs.

STATUS
CONFIRMED

SOURCE
PR #73 — lightweight GGUF download