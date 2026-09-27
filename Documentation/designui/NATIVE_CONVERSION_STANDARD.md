# Design Token → Native Conversion Standard

## Purpose

Define the small, repeatable step that converts Design Tokens into native iOS components.

This is an implementation workflow, not a new architecture layer.

## Canonical flow

Design Image → Design Data → Design Tokens → **Native Components** → SwiftUI → Visual Verification

## Rules

1. Read the approved Design Tokens as the source of truth.
2. Map semantic token groups to native component responsibilities.
3. Create small native components with clear boundaries.
4. Do not copy screenshot coordinates into SwiftUI.
5. Do not invent visual values that are absent from Design Tokens.
6. Keep UI/design logic out of Kernel, Runtime, Provider, Memory, and Module contracts.
7. Keep Agent/living elements semantic and state-driven.
8. Compose the final screen from native components.
9. Verify on the target iPhone/device and fix the responsible token or component.

## Token → Component mapping

| Design Token | Native responsibility |
|---|---|
| Color / Typography | View styling |
| Spacing / Sizing | Layout constants |
| Radius / Surface | Shape and container styling |
| Shadow / Glow | Visual modifiers/effects |
| Motion | State-driven animation |
| Component tokens | Component-specific configuration |
| State tokens | UI state presentation |

Example:

- agent.orb.size → AgentCoreDot size
- agent.orb.glow → AgentCoreDot glow
- agent.orb.state.thinking → AgentCoreDot thinking animation

## Component boundary

Prefer semantic components such as:

AgentSurface
├── Background
├── AgentCoreDot
├── ContextualControls
└── ComposerPill

over one large screen containing all visual implementation.

The Agent remains a living dot/orb when that is what the Design Data specifies. Do not turn it into an avatar or character.

## SwiftUI rule

SwiftUI is the rendering/composition layer.

Design Tokens → Native Components → SwiftUI

SwiftUI must not become a second source of design decisions.

## Conversion checklist

- [ ] Read Design Data
- [ ] Read approved Design Tokens
- [ ] Map tokens to semantic components
- [ ] Define component boundaries
- [ ] Implement components in SwiftUI
- [ ] Bind documented states/motion
- [ ] Build on native iOS target
- [ ] Visually verify
- [ ] Correct token/component rather than scattered overrides

## Non-goals

This document does not define:

- Kernel architecture
- Runtime behavior
- Provider contracts
- Memory architecture
- Module contracts
- A new UI framework
- Automatic design-code generation

## Core principle

**Tokens define the visual vocabulary. Native Components give that vocabulary behavior and structure. SwiftUI renders the result.**