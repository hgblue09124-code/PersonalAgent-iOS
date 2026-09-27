# DESIGN_DATA_PersonalAgent_Splash

## 1. Design Identity

| Field | Value |
|---|---|
| Design name | Personal Agent — Splash / Welcome Screen |
| Image/source identifier | Uploaded composite JPG (two variants side by side) |
| Number of reference images | 1 composite image containing 2 UI states (color variants) |
| Intended platform | iOS (iPhone) |
| Device/frame | iPhone with Dynamic Island (Pro-style frame) |
| Orientation | Portrait |
| UI state | Idle / first-launch welcome screen, 2 color variants (Blue, Green) |
| Confidence level | MEDIUM — single static composite, no interaction frames |

## 2. Canvas

Two phone frames side by side in one image. Values below are per-phone-frame, ESTIMATED from proportions (no metadata available).

| Property | Value | Confidence |
|---|---|---|
| Width (per frame) | ~600 px | ESTIMATED |
| Height (per frame) | ~1265 px | ESTIMATED |
| Aspect ratio | ≈ 9:19.5 | ESTIMATED |
| Orientation | Portrait | MEASURED |
| Safe areas | Standard iOS safe areas | UNKNOWN |

## 3. Layout Map

| Component | Type | Position | Size | Parent | Alignment | Notes |
|---|---|---|---|---|---|---|
| StatusBar | System | Top edge | Full width | Screen | Top | Standard iOS |
| DynamicIsland | System | Top-center | Small pill | Screen | Top-center | Standard hardware |
| AppIcon | Component | Top-left | Small rounded-square | Screen | Top-left | Dark icon tile |
| MenuButton | Component | Top-right | Small circle | Screen | Top-right | Circular outline + hamburger |
| HeadlineTitle | Text | Upper-mid | Large, 2 lines | Screen | Left | “Personal / Agent” |
| Subheadline | Text | Below title | Medium, 2 lines | Screen | Left | “Let’s make / it happen.” |
| RunnerFigure | Illustration | Center-lower | Large | Screen | Center-left | Abstract running silhouette |
| AgentOrb | Living element | Figure head position | Medium sphere | RunnerFigure visual | Center | Glossy glass sphere |
| MotionSquiggle | Graphic | Near trailing foot | Small | Screen | — | Static speed cue |
| TornPaperTag | Component | Bottom-left | Medium | Screen | Bottom-left | Torn/sticker-style card |
| ComposerPill | Component | Bottom-right | Medium | Screen | Bottom-right | Sparkle + Composer / Start here + arrow |
| HomeIndicator | System | Bottom-center | Thin bar | Screen | Bottom-center | Standard iOS |

Z-order: Background → RunnerFigure → AgentOrb → MotionSquiggle → TornPaperTag → ComposerPill → system/top chrome.

## 4. Visual Hierarchy

1. Primary: “Personal Agent” headline, closely competing with RunnerFigure + AgentOrb.
2. Secondary: subheadline and ComposerPill.
3. Tertiary: TornPaperTag, MotionSquiggle, AppIcon, MenuButton.
4. Minimal: system chrome.

AgentOrb is the optical center of the lower hero graphic, but not the sole dominant focal point.

## 5. Color Data

### Variant A — Blue

| Token | HEX | Opacity | Role | Confidence |
|---|---|---|---|---|
| background.primary | ~#1B2FE0 | 100% | Screen background | ESTIMATED |
| text.onBackground.primary | #FFFFFF | 100% | Headline | ESTIMATED |
| text.onBackground.secondary | ~#0A0A1E | 100% | Subheadline | ESTIMATED |
| figure.fill | #FFFFFF | 100% | RunnerFigure | ESTIMATED |
| agent.orb.fill | ~#2A3FE8 | ~90% | AgentOrb | ESTIMATED |
| tag.background | ~#0A0A0A | 100% | Tag | ESTIMATED |
| tag.text | #FFFFFF | 100% | Tag text | ESTIMATED |
| composer.background | ~#0A0A2E | 100% | ComposerPill | ESTIMATED |
| composer.text | #FFFFFF | 100% | Composer text/icons | ESTIMATED |

### Variant B — Green

| Token | HEX | Opacity | Role | Confidence |
|---|---|---|---|---|
| background.primary | ~#1FE08A | 100% | Screen background | ESTIMATED |
| text.onBackground.primary | ~#0A0A0A | 100% | Headline | ESTIMATED |
| text.onBackground.secondary | #FFFFFF | 100% | Subheadline | ESTIMATED |
| figure.fill | ~#0A0A0A | 100% | RunnerFigure | ESTIMATED |
| agent.orb.fill | ~#1FA860 | ~90% | AgentOrb | ESTIMATED |
| tag.background | #FFFFFF | 100% | Tag | ESTIMATED |
| tag.text | ~#0A0A0A | 100% | Tag text | ESTIMATED |
| composer.background | ~#0A0A0A | 100% | Composer | ESTIMATED |
| composer.text | #FFFFFF | 100% | Composer text | ESTIMATED |

Pattern: same composition with systematic contrast/theme inversion.

## 6. Typography

| Token | Content | Family | Size | Weight | Notes |
|---|---|---|---|---|---|
| text.title | Personal Agent | Bold condensed grotesque sans | ~56–64pt equivalent | 900 | Family UNKNOWN |
| text.subhead | Let's make it happen. | Same family | ~26–30pt | 700 | Tight |
| text.tagLabel | GET THINGS MOVING / PLAN CREATE MOVE | Marker-style display | ~18–22pt | Bold | Family UNKNOWN |
| text.composerTitle | Composer | UI sans | ~14pt | 600–700 | |
| text.composerSubtitle | Start here | UI sans | ~12pt | 400–500 | |

## 7. Surface Data

| Surface | Treatment |
|---|---|
| AppIcon | Solid dark rounded-square |
| MenuButton | Transparent circular outline |
| AgentOrb | Glossy translucent sphere, colored core, glass rim/highlight, soft shadow |
| TornPaperTag | Flat irregular torn-edge shape |
| ComposerPill | Solid dark full pill |
| RunnerFigure | Flat solid silhouette |

## 8. Agent / Living Element — AgentOrb

| Property | Value | Confidence |
|---|---|---|
| Semantic role | Agent represented as sphere replacing runner head | INFERRED |
| Shape | Sphere / glass orb | OBSERVED |
| Center | Runner head/neck anchor | ESTIMATED |
| Diameter | Large relative to figure neck | ESTIMATED |
| Base color | Variant accent | OBSERVED |
| Glow | Small, low–medium glass highlight | ESTIMATED |
| Outer rings | None | OBSERVED |
| Particles | None | OBSERVED |
| Interaction | UNKNOWN | UNKNOWN |

The supplied image only evidences idle/welcome. Do not invent additional Agent states.

## 9. State Model

| State | Evidence |
|---|---|
| idle | OBSERVED |
| thinking / working / checking / result / failed | UNKNOWN — no supporting frames |

## 10. Motion Data

No animation frames were supplied. Timing, easing and repetition are TIMING_UNKNOWN. MotionSquiggle is a static decorative speed cue.

## 11. Interaction Map

| Component | Interaction | Evidence |
|---|---|---|
| MenuButton | tap → menu/settings | INFERRED |
| ComposerPill | tap → composer/input | INFERRED |
| AppIcon | tap | UNKNOWN |
| AgentOrb / RunnerFigure | tap | UNKNOWN |

## 12. Contextual UI

No settings, history, model, provider or overlay surfaces are shown. Their presentation is UNKNOWN.

## 13. Component Inventory

- AppIcon
- MenuButton
- HeadlineTitle
- Subheadline
- RunnerFigure
- AgentOrb — reusable Agent visual
- MotionSquiggle
- TornPaperTag
- ComposerPill

## 14. Design Tokens

```yaml
colors:
  variantA_blue:
    background.primary: "#1B2FE0"     # ESTIMATED
    text.onBackground.primary: "#FFFFFF"
    text.onBackground.secondary: "#0A0A1E"
    figure.fill: "#FFFFFF"
    agent.orb.fill: "#2A3FE8"
    tag.background: "#0A0A0A"
    tag.text: "#FFFFFF"
    composer.background: "#0A0A2E"
    composer.text: "#FFFFFF"
  variantB_green:
    background.primary: "#1FE08A"     # ESTIMATED
    text.onBackground.primary: "#0A0A0A"
    text.onBackground.secondary: "#FFFFFF"
    figure.fill: "#0A0A0A"
    agent.orb.fill: "#1FA860"
    tag.background: "#FFFFFF"
    tag.text: "#0A0A0A"
    composer.background: "#0A0A0A"
    composer.text: "#FFFFFF"
typography:
  text.title:
    weight: 900
    lineHeight: tight
  text.subhead:
    weight: 700
    lineHeight: tight
  text.tagLabel:
    weight: bold
    case: uppercase
  text.composerTitle:
    weight: 600-700
  text.composerSubtitle:
    weight: 400-500
spacing: UNKNOWN
sizing:
  agent.orb.diameter: ESTIMATED_LARGE_RELATIVE_TO_FIGURE_NECK
radius:
  composer.pill: full
  appIcon: medium
  tag: irregular_torn_edge
surface:
  agentOrb.glass: true
shadow:
  composerPill: soft_drop_shadow
  tag: soft_drop_shadow
glow:
  agentOrb.highlight: low_medium
motion:
  idlePulse: TIMING_UNKNOWN
  motionSquiggle: static_decorative_only
opacity:
  agentOrb.fill: ~0.9
```

## 15. Responsive Rules

- AppIcon/MenuButton anchor to safe-area top edges.
- Headline follows the top control row.
- Subheadline follows headline.
- RunnerFigure occupies the lower ~60% and scales proportionally.
- AgentOrb anchors to RunnerFigure head position.
- TornPaperTag anchors bottom-leading safe area.
- ComposerPill anchors bottom-trailing safe area.
- System chrome remains OS-controlled.

Prefer relational/proportional layout over screenshot pixel coordinates.

## 16. Light / Dark

The references show two brand variants, not a true light/dark pair. Layout and typography are shared; contrast and surface colors invert. True dark-mode behavior is UNKNOWN.

## 17. Evidence & Confidence

OBSERVED/MEASURED: layout, component presence/position, two-variant structure, absence of orb rings/particles.

INFERRED: MenuButton/ComposerPill actions and AgentOrb semantic role.

ESTIMATED: HEX values, sizes, spacing, radii.

UNKNOWN: exact device resolution/safe areas, fonts, animation timing, contextual UI, hero interaction, whether Blue/Green are runtime themes.

## 18. Implementation Handoff

Implement native SwiftUI from this data through:

**Design Data → Design Tokens → Native Components → SwiftUI → visual verification**

Required components: AppIcon, MenuButton, HeadlineTitle, Subheadline, RunnerFigure, AgentOrb, MotionSquiggle, TornPaperTag, ComposerPill.

Do not invent unsupported states, timing, interaction or exact visual values. Preserve UNKNOWN/ESTIMATED/INFERRED provenance.

Do not modify Kernel, Runtime, Provider, Memory, Module contracts or introduce an architecture layer for this design work.
