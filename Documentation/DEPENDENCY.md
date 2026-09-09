# Dependency Direction

Arrows mean "may import".

```
App
  -> PAComposition
    -> PAKernel
      -> PAAgency / PACognition / PAPolicy / PAEvents / PAObservability
        -> PASkills / PATools / PAModules / PAProviders / PAMemory
          -> PAStorage / PASecurity
            -> PAFoundation
```

## Forbidden

- Kernel importing a concrete provider module (`PAProvidersGrok`, `PAProvidersOpenAI`, ...)
- Kernel importing SwiftUI / UIKit
- Any Core module importing App screens
- Living Data Ocean, Firebase, Supabase as required runtime packages
- Provider owning AgentState
- Skill mutating UI
- Tool bypassing Policy
- Global singleton service locators

## Reserved provider packages

`PAProvidersGrok`, `PAProvidersOpenAI`, `PAProvidersOpenAICompatible`, `PAProvidersLocal`
exist so M2 has a place to land. Composition may wire them later.
Kernel must not import them.
