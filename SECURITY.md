# Security Policy

## Reporting a vulnerability

Please do not disclose exploitable vulnerabilities, credentials, personal data, or private model files in a public issue or pull request. Use GitHub's private vulnerability reporting / Security Advisories for this repository when available. If private reporting is not enabled, contact the repository maintainer privately through their GitHub profile before publishing details.

Include the affected version or commit, impact, a minimal reproduction, and relevant sanitized logs. Do not include live API keys, access tokens, private conversation content, or GGUF/model binaries.

## Security boundaries

- Provider credentials belong in Keychain using device-only accessibility; never in source, UserDefaults, chat history, or logs.
- Imported files are untrusted input. Validate file type/content and enforce size and extraction limits; unsupported or malformed files must fail closed.
- GitHub sync must reject secret-like content, avoid forced branch updates, verify object hashes, and report conflicts rather than silently overwriting edits.
- Terminal and skill execution must stay inside the workspace/runtime permission boundary.
- CI success does not prove physical-device acceptance or live-provider credentials work end to end.
