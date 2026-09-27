# DesignUI Standard

DesignUI is the repository-level standard for converting visual UI designs into native iOS UI.

## Canonical pipeline

Design Image → Design Data → Design Tokens → Native Components → SwiftUI → Visual Verification

Do not skip the Design Data step when a design image is the source of truth.

## 1. Design Image → Design Data

Treat the image as evidence, not as implementation instructions.

Extract, where supported by the image:

- Canvas: device/frame, viewport, orientation, safe area
- Layout: bounds, alignment, spacing, hierarchy, constraints
- Color: background, primary/secondary/accent colors, opacity
- Typography: family, size, weight, line height, tracking, alignment
- Surface: radius, fill, blur, border, shadow, glow
- Components: semantic UI components
- Motion: visible state/behavior and only motion supported by evidence
- Interaction: observed interactions; inferred interactions must be labeled
- Responsive rules
- Light/dark variants
- Evidence and confidence

Use semantic names such as `AgentCoreDot`, not screenshot descriptions such as “small blue circle”.

Unknown values must remain `UNKNOWN` or `ESTIMATED` with confidence. Never invent exact values.

## 2. Design Data → Design Tokens

Normalize measurable visual values into reusable tokens.

Typical token groups:

- Colors
- Typography
- Spacing
- Sizing
- Radius
- Surface
- Shadow
- Glow
- Motion
- Opacity

Tokens are the bridge between design specification and implementation.

## 3. Design Tokens → Native Components

Turn semantic design elements into native components with clear boundaries.

Example:

```text
AgentSurface
├── Background
├── HeadlineTitle
├── AgentCoreDot
├── ContextualControls
└── ComposerPill
```

Do not build a single monolithic screen when the design contains reusable semantic elements.

## 4. Native Components → SwiftUI

Compose the screen from native components and tokens.

SwiftUI should implement the Design Data; it should not become a second source of design decisions.

Keep UI/design concerns out of Kernel, Runtime, Provider, Memory, and Module contracts.

## 5. State and motion

Design states must map to real UI state.

Example:

```text
idle → thinking → working → checking → result / failed
```

Only implement states supported by the design and product behavior. Unknown animation timing remains unknown until validated.

## 6. Visual verification

After implementation:

1. Build the native UI.
2. Capture the target device/simulator frame.
3. Compare against the source design.
4. Fix the token/component causing the mismatch.
5. Re-verify.

Prefer correcting Design Tokens or Native Components over scattered per-view overrides.

## Core rule

**The image describes the look. Design Data describes what the UI is. Tokens normalize it. Native Components implement it. SwiftUI composes it. Visual Verification closes the loop.**

DesignUI is a UI/design workflow, not an application architecture layer.
