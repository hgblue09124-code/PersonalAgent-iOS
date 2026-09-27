# cllama — Official llama.cpp Native Integration Particle

This module provides the native C/C++ binding surface for `llama.cpp` on Apple platforms (iOS / macOS).

## Upstream Provenance (Gate 1)

- **Official Repository**: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- **Upstream Revision / Commit**: `6f41ac59e0a49a00483a316a22ada6b04edd2950` (release tag `b11070`)
- **Canonical iOS Integration**: Official `build-xcframework.sh` build path from `llama.cpp` producing `llama.xcframework`.

## Architectural Boundary

```text
PersonalAgent
  → PAComposition
  → PAProvidersLocal
  → LocalModelProviderAdapter
  → LlamaCPPModelEngine
  → cllama
  → Frameworks/llama.xcframework (llama.framework)
```

- **Metal Acceleration**: Enabled via `-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON`. `llama.framework` includes `ggml-metal.h` and links the system Metal framework.
- **Platform Separation**: On Apple platforms (`iOS`, `macOS`), `cllama` re-exports `llama.framework`. On Linux, `cllama` is excluded via platform conditions, maintaining a green headless test suite.
