# Dependency Direction

Arrows mean "may import".

```
App
  -> PAComposition
    -> PAKernel
      -> PAAgency / PACognition / PAPolicy / PAEvents / PAObservability / PAProviders
        -> PASkills / PATools / PAModules / PAMemory
          -> PAStorage / PASecurity
            -> PAFoundation

PAProviders
  -> PAFoundation / PAObservability / PASecurity / PAEvents

PAProvidersGrok / OpenAI / OpenAICompatible / Local
  -> PAProviders / PAFoundation
```

## Forbidden

- Kernel importing a concrete provider module (`PAProvidersGrok`, `PAProvidersOpenAI`, ...)
- Kernel importing SwiftUI / UIKit / URLSession
- Any Core module importing App screens
- Living Data Ocean, Firebase, Supabase as required runtime packages
- Provider owning AgentState
- Skill mutating UI
- Tool bypassing Policy
- Global singleton service locators
- Secrets in Kernel state, events, logs, or source control

## Provider packages

`PAProviders` is the semantic contract and provider runtime.
Concrete adapters live in reserved packages and are wired only through Composition or tests.
The Xcode app target does not link those concrete packages.
