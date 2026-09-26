# ipa-verification
ID
ipa-verification

PURPOSE
Make Apple build artifacts independently verifiable for physical iPhone testing.

WHEN
CI produces an unsigned development IPA.

RULE
Harden the IPA verification path so every Apple build yields a verifiably valid artifact; do not mix this with runtime/product changes.

VERIFY
PR #78 is explicitly agent/IPA verification work with no runtime/product code changes.

STATUS
CONFIRMED

SOURCE
PR #78 — AGENTS optimization and IPA pre-release verification