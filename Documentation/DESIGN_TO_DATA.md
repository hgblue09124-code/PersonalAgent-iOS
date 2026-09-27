# Design-to-Data

## Purpose

Define the intermediate representation between visual design and native UI implementation.

**Design image → Design Data → Design Tokens → Native Components → SwiftUI**

This is an implementation method, not a new product feature or art direction.

## Principle

Do not ask an implementation agent to reproduce a screenshot by visual guessing.

A design image is a source of evidence. Extract measurable and semantic information into structured data first, then implement from that data.

## Design Data

### Canvas
- device / viewport
- width / height
- safe areas
- orientation

### Layout
- element bounds
- position
- alignment
- spacing
- hierarchy
- constraints

### Color
- background
- primary
- secondary
- accent
- opacity

### Typography
- family
- size
- weight
- line height
- tracking
- alignment

### Surface
- radius
- fill
- opacity
- blur
- border
- shadow
- glow

### Components
Identify reusable semantic components rather than screenshot regions.

Example:

```
AgentSurface
├── AgentCoreDot
├── AgentStatus
├── ContextPrompt
└── FloatingControls
```

### Motion

Represent behavior, not just appearance.

Example:

```
idle
thinking
working
checking
result
failed
```

Each state may define:
- scale
- opacity
- glow
- duration
- easing
- repetition

## Concept SAO Example

The central Agent should be represented semantically:

```
Agent:
  type: living_dot
  position: center
  interaction: tap
  states:
    idle
    thinking
    working
    checking
    result
    failed
```

The dot is a real native component, not an image.

SAO/anime references describe atmosphere and spatial language; they do not require copying characters or scenes.

## Output

The Design Data layer should be sufficient to derive:

```
DesignData
    ↓
DesignTokens
    ↓
AgentCoreDot
AgentSurface
FloatingControls
    ↓
SwiftUI
```

## Boundary

Design-to-Data must not introduce a new runtime architecture layer.

It belongs to the UI/design implementation workflow and must not leak into Kernel, Runtime, Provider, Memory, or Module contracts.

## Future automation

A future design-analysis agent may inspect a supplied image and produce Design Data automatically.

Do not build a parser, rigid schema, database, or automated design compiler until real design work demonstrates that it is needed.

## North Star

**The image describes the look. Design Data describes what the UI is. SwiftUI implements it.**

This document is intentionally separate from the product issue so the implementation issue remains focused on the user-visible UI outcome.
