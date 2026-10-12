# AgentOS soft-update manifest

The Settings → AgentOS Soft Update panel reads `agentos-update.json` from the configured GitHub repository and branch. The fetch is read-only; it never commits or pushes.

## Manifest contract

- `repository`: exact `owner/repository` identity.
- `baseRevision`: revision currently installed on the device. First-time devices use `initial`.
- `revision`: stable identifier for this update; after activation the app stores it locally.
- `compatibility`: currently `runtime-v1`.
- `files[]`: allowlisted relative path, UTF-8 byte count, SHA-256 of the new bytes, and `baseSHA256` of the currently installed bytes. Use `missing` only when the target file must not exist before installation.

Only Markdown, JSON, and text files beneath `agents/`, `skills/`, `modules/`, `tools/`, `config/`, `workspace/`, or `.agent/` are eligible. Keep the manifest itself out of `files[]`.

## Publishing the next update

1. Change the intended definition file(s) in the repository.
2. Compute each new file's UTF-8 byte count and SHA-256.
3. Set `baseSHA256` to the previously shipped file hash (or `missing` for a new file).
4. Set `baseRevision` to the prior manifest's `revision`, and choose a new unique `revision`.
5. Commit the files and manifest together. The app downloads into staging, checks repository/revision/path/size/hash/local base hashes, then requires explicit activation.
6. If a user edited a target file locally, the update is rejected rather than overwriting it. Manual rollback restores only files still matching the update hash; if a target was edited after activation, rollback is blocked for safety.

Native Swift, UI, frameworks, entitlements, and executable code are never soft-updated; those require a new signed app build.
