# Contributing

## Change discipline

- One logical task per commit; prefer a squash merge so each task lands as one commit.
- Confirm the root cause before changing code. Keep repairs minimal and add a regression test for every reproducible defect.
- Preserve module boundaries: UI presents capabilities; Kernel contracts remain independent of concrete provider vendors.
- Never commit API keys, tokens, user data, GGUF/model binaries, generated IPA files, or private test fixtures.

## Validation

Before requesting merge:

1. Run the focused regression tests and swift test --disable-sandbox where available.
2. Require both M3 and Apple Native Build & Unsigned IPA to pass on the final PR head.
3. Review the actual diff and CI job evidence; a test file existing is not proof the behavior works.
4. Treat cancellation, malformed output, unsupported formats, credential failures, and sync conflicts as explicit failures—not success.
5. Keep physical iPhone, real GGUF, and live remote-provider acceptance separate from CI-only claims.

## Import and sync contracts

The import gateway may safely store arbitrary regular files, but only registered readers may claim successful extraction. Readers must enforce byte/pixel/page/output limits and never execute imported content. Sync must fail closed on unsafe paths, secret-like data, hash mismatch, or divergent edits.
