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

---

## 2. Canvas

Two phone frames side by side in one image. Values below are per-phone-frame, ESTIMATED from proportions (no metadata available).

| Property | Value | Confidence |
|---|---|---|
| Width (per frame) | ~600 px (image px, not device px) | ESTIMATED |
| Height (per frame) | ~1265 px (image px) | ESTIMATED |
| Aspect ratio | ≈ 9:19.5 (matches iPhone Pro screens) | ESTIMATED |
| Orientation | Portrait | MEASURED |
| Safe area top | Status bar + Dynamic Island height | UNKNOWN (exact px) |
| Safe area bottom | Home indicator bar height | UNKNOWN (exact px) |
| Safe area left/right | Standard device margins | UNKNOWN |

---

## 3. Layout Map

| Component | Type | Position | Size | Parent | Alignment | Notes |
|---|---|---|---|---|---|---|
| StatusBar | System | Top edge | Full width, small height | Screen | Top | Time "9:41", signal, WiFi, battery — standard iOS |
| DynamicIsland | System | Top-center | Small pill | Screen | Top-center | Standard hardware element |
| AppIcon | Component | Top-left | Small rounded-square | Screen | Top-left | Dark icon tile with running-figure glyph |
| MenuButton | Component | Top-right | Small circle | Screen | Top-right | Circular outline button, hamburger icon |
| HeadlineTitle | Text | Upper-mid, left-aligned | Large, 2 lines | Screen | Left | "Personal / Agent" |
| Subheadline | Text | Below title, left-aligned | Medium, 2 lines | Screen | Left | "Let's make / it happen." |
| RunnerFigure | Illustration | Center-lower, large | Large (dominant graphic) | Screen | Center-left leaning | Abstract running-person silhouette, no head (head replaced by orb) |
| AgentOrb | Living element | Overlaps RunnerFigure's head position | Medium sphere | RunnerFigure (visually), independent layer | Centered on figure's neck/head area | Glossy glass-sphere with colored fill, treated as the "head"/Agent |
| MotionSquiggle | Graphic | Near figure's trailing foot, right side | Small | Screen | — | Hand-drawn zig-zag lines implying speed/motion |
| TornPaperTag | Component | Bottom-left | Medium, irregular rotated rectangle | Screen | Bottom-left | Rough torn/sticker-style card with bold marker text |
| ComposerPill | Component | Bottom-right | Medium rounded pill | Screen | Bottom-right | Sparkle icon + "Composer / Start here" text + arrow icon |
| HomeIndicator | System | Bottom-center | Thin bar | Screen | Bottom-center | Standard iOS home indicator |

Z-order (back to front): Background color → RunnerFigure silhouette → AgentOrb (overlapping figure) → MotionSquiggle → TornPaperTag → ComposerPill → StatusBar/AppIcon/MenuButton (top chrome) → HomeIndicator.

---

## 4. Visual Hierarchy

1. **Primary focus:** The bold two-line "Personal Agent" headline, competing closely with the large RunnerFigure + AgentOrb graphic which dominates screen area.
2. **Secondary elements:** Subheadline "Let's make it happen.", ComposerPill (call to action).
3. **Tertiary elements:** TornPaperTag callout, MotionSquiggle, AppIcon, MenuButton.
4. **Minimal/quiet elements:** StatusBar, HomeIndicator (system chrome, low visual weight by design).
5. **Flow of attention:** Top-left icon → headline text → down into the large figure/orb graphic → tag callout (bottom-left) → composer CTA (bottom-right).

**Is the Agent the visual center?** PARTIALLY. The AgentOrb (glossy sphere) sits at the compositional center of the lower graphic and functions as the figure's "head," but the overall focal weight is shared between the headline typography and the full-body RunnerFigure illustration — the orb alone is not the dominant single focal point. Confidence: MEDIUM (INFERRED).

---

## 5. Color Data

Two palettes (one per variant). HEX values are ESTIMATED (read from a compressed image, not color-picked from source assets).

### Variant A — "Blue"
| Token | HEX (est.) | Opacity | Role | Confidence |
|---|---|---|---|---|
| background.primary | ~#1B2FE0 | 100% | Screen background | ESTIMATED |
| text.onBackground.primary | #FFFFFF | 100% | Headline title | ESTIMATED |
| text.onBackground.secondary | ~#0A0A1E (near-black) | 100% | Subheadline "Let's make it happen." | ESTIMATED |
| figure.fill | #FFFFFF | 100% | RunnerFigure silhouette | ESTIMATED |
| agent.orb.fill | ~#2A3FE8 (mid-blue, glassy) | ~90% | AgentOrb sphere | ESTIMATED |
| tag.background | ~#0A0A0A | 100% | TornPaperTag surface | ESTIMATED |
| tag.text | #FFFFFF | 100% | TornPaperTag text | ESTIMATED |
| composer.background | ~#0A0A2E (near-black/navy) | 100% | ComposerPill surface | ESTIMATED |
| composer.text | #FFFFFF | 100% | ComposerPill text/icons | ESTIMATED |
| composer.iconAccent | ~#2A3FE8 | 100% | Sparkle icon circle | ESTIMATED |

### Variant B — "Green"
| Token | HEX (est.) | Opacity | Role | Confidence |
|---|---|---|---|---|
| background.primary | ~#1FE08A | 100% | Screen background | ESTIMATED |
| text.onBackground.primary | ~#0A0A0A | 100% | Headline title | ESTIMATED |
| text.onBackground.secondary | #FFFFFF | 100% | Subheadline | ESTIMATED |
| figure.fill | ~#0A0A0A | 100% | RunnerFigure silhouette | ESTIMATED |
| agent.orb.fill | ~#1FA860 (mid-green, glassy) | ~90% | AgentOrb sphere | ESTIMATED |
| tag.background | #FFFFFF | 100% | TornPaperTag surface | ESTIMATED |
| tag.text | ~#0A0A0A | 100% | TornPaperTag text | ESTIMATED |
| composer.background | ~#0A0A0A | 100% | ComposerPill surface | ESTIMATED |
| composer.text | #FFFFFF | 100% | ComposerPill text/icons | ESTIMATED |
| composer.iconAccent | ~#1FE08A | 100% | Sparkle icon circle | ESTIMATED |

Pattern: the two variants are a systematic light/inverted swap of the same token set (background↔figure/text contrast flips), suggesting a themeable color-token system rather than two unrelated designs.

---

## 6. Typography

| Token | Text content | Font family | Size (est.) | Weight | Line height | Tracking | Alignment | Color |
|---|---|---|---|---|---|---|---|---|
| text.title | "Personal Agent" (2 lines) | Bold condensed grotesque sans (identity unclear) | ~56–64pt-equivalent | Black/Heavy (900) | Tight (~0.9) | Normal/slightly tight | Left | Variant-dependent (white / near-black) |
| text.subhead | "Let's make it happen." | Same family as title, bold | ~26–30pt-equivalent | Bold (700) | Tight | Normal | Left | Variant-dependent |
| text.tagLabel | "GET THINGS MOVING" / "PLAN CREATE MOVE" | Distinct marker/handwritten bold display face | ~18–22pt-equivalent | Bold, all-caps | Tight | Slightly loose | Left, stacked | Variant-dependent |
| text.composerTitle | "Composer" | Same family as body UI, bold | ~14pt-equivalent | Bold (600–700) | Normal | Normal | Left | White |
| text.composerSubtitle | "Start here" | Same family, regular | ~12pt-equivalent | Regular/Medium | Normal | Normal | Left | White, slightly reduced opacity |

Font family cannot be identified with certainty — recorded as a bold grotesque/condensed sans for titles and a separate hand-lettered marker face for the tag callout. Confidence: LOW–MEDIUM.

---

## 7. Surface Data

| Surface | Fill | Radius | Border | Blur | Shadow | Glow |
|---|---|---|---|---|---|---|
| AppIcon | Solid dark, rounded-square | Medium (app-icon-style) | None observed | None | Subtle drop shadow (INFERRED) | None |
| MenuButton | Transparent w/ thin outline circle | Full (circular) | 1–2px stroke | None | None | None |
| AgentOrb | Glossy translucent sphere w/ colored core, glass rim highlight | Full (circular/spherical) | Thin light rim/highlight | Slight (glass refraction look) | Soft drop shadow beneath sphere | Subtle inner glow/highlight arc at top |
| TornPaperTag | Solid flat fill, irregular torn-edge silhouette | Irregular (non-rectangular, hand-cut look) | None | None | Slight drop shadow (INFERRED) | None |
| ComposerPill | Solid dark fill | Full pill (fully rounded ends) | None | None | Soft drop shadow (INFERRED) | None |
| RunnerFigure | Flat solid silhouette | N/A (illustrative shape) | None | None | None | None |

---

## 8. Agent / Living Element — **AgentOrb**

| Property | Value | Confidence |
|---|---|---|
| Semantic role | Represents "the Agent" as a glossy sphere replacing the runner figure's head | MEDIUM (INFERRED) |
| Center position | Approx. where the figure's head/neck would sit, upper-center of the RunnerFigure mass | ESTIMATED |
| Diameter | Roughly 1.4–1.6× the width of the figure's "neck" — a noticeably large sphere relative to the body | ESTIMATED |
| Shape | Sphere / glass orb | MEASURED |
| Base color | Matches background accent (blue in Variant A, green in Variant B) | MEASURED |
| Glow radius | Small — soft highlight, not a large radiant halo | ESTIMATED |
| Glow intensity | Low–medium; primarily a glass specular highlight rather than emissive glow | ESTIMATED |
| Outer rings | None observed | OBSERVED (absence) |
| Particle effects | None observed | OBSERVED (absence) |
| Visual hierarchy | High — sits at the optical center of the lower graphic composition | INFERRED |
| Interaction target | UNKNOWN — no interaction frames provided | UNKNOWN |
| Surrounding spacing | Orb overlaps the figure's silhouette directly; no isolated padding | OBSERVED |

Note: this is a single static idle-style representation; no additional states (thinking/working/etc.) are evidenced in the source image.

---

## 9. State Model

Only one state is evidenced per variant: a static **idle/welcome** presentation. The two variants (Blue, Green) appear to be **theme/color variants**, not functional UI states.

| State | Evidence |
|---|---|
| idle (default welcome) | OBSERVED — both variants show the same layout/content structure |
| thinking / working / checking / result / failed | Not supported by evidence — TIMING_UNKNOWN / STATE_UNKNOWN |

---

## 10. Motion Data

No animation frames or motion-comparison images were supplied.

| Animation | Property | From | To | Duration | Easing | Repeat | State |
|---|---|---|---|---|---|---|---|
| (none observable) | — | — | — | TIMING_UNKNOWN | TIMING_UNKNOWN | TIMING_UNKNOWN | — |

The MotionSquiggle graphic (hand-drawn zig-zag near the figure's foot) is a **static illustrative cue implying motion/speed**, not an actual animation — INFERRED, not OBSERVED motion.

---

## 11. Interaction Map

| Component | Interaction type | Visible affordance | Target area | Resulting state |
|---|---|---|---|---|
| MenuButton | tap | Circular outlined icon button | Top-right, small | Likely opens a menu/settings surface — INFERRED |
| ComposerPill | tap | Rounded pill, "Start here" label, arrow icon | Bottom-right | Likely opens a composer/input surface — INFERRED |
| AppIcon | tap (uncertain) | Icon tile | Top-left | UNKNOWN — could be a home/brand tap target |
| TornPaperTag | none evidenced | Static decorative callout | Bottom-left | OBSERVED as non-interactive; no affordance cues (no chevron/button styling) |
| AgentOrb / RunnerFigure | tap (uncertain) | Large central graphic | Center | UNKNOWN — no affordance styling (no button chrome), likely decorative — INFERRED non-interactive |

---

## 12. Contextual UI

No contextual/overlay surfaces (settings sheets, popovers, history panels) are shown in the source image. Their existence, trigger, and presentation style are **UNKNOWN** and would require additional reference frames.

---

## 13. Component Inventory

| Component | Responsibility | Parent | State dependencies | Interaction | Reusable? |
|---|---|---|---|---|---|
| AppIcon | Brand mark | Screen | None observed | Unknown | Reusable (likely global nav element) |
| MenuButton | Entry point to menu/settings | Screen | None observed | tap (inferred) | Reusable |
| HeadlineTitle | Primary marketing headline | Screen | Static copy | None | Screen-specific |
| Subheadline | Supporting tagline | Screen | Static copy | None | Screen-specific |
| RunnerFigure | Hero illustration | Screen | Color theme variant | None (inferred) | Screen-specific (theme-driven) |
| AgentOrb | Represents the Agent/AI presence | Overlaps RunnerFigure | Color theme variant; likely also functional state (idle/thinking/etc. in the live app) | Unknown | Reusable (core Agent component) |
| MotionSquiggle | Decorative motion cue | Screen | Color theme variant | None | Screen-specific |
| TornPaperTag | Marketing callout / value prop | Screen | Copy + theme variant | None observed | Screen-specific |
| ComposerPill | Primary CTA into composer/input | Screen | Color theme variant | tap (inferred) | Reusable (likely persists across screens) |

---

## 14. Design Tokens

Only values with reasonable support from the image are included; most are ESTIMATED.

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

spacing: UNKNOWN   # no measurable grid evidence

sizing:
  agent.orb.diameter: ESTIMATED_LARGE_RELATIVE_TO_FIGURE_NECK

radius:
  composer.pill: full
  appIcon: medium
  tag: irregular_torn_edge

surface:
  agentOrb.glass: true

shadow:
  composerPill: soft_drop_shadow      # INFERRED
  tag: soft_drop_shadow               # INFERRED

glow:
  agentOrb.highlight: low_medium      # ESTIMATED

motion:
  idlePulse: TIMING_UNKNOWN
  motionSquiggle: static_decorative_only

opacity:
  agentOrb.fill: ~0.9                 # ESTIMATED
```

---

## 15. Responsive Rules

Based on visual composition (rules expressed relationally where supported):

```
AppIcon.topLeading = safeArea.topLeading + spacing
MenuButton.topTrailing = safeArea.topLeading + spacing   // top-trailing
HeadlineTitle.top = below(AppIcon/MenuButton row) + spacing
Subheadline.top = below(HeadlineTitle) + spacing
RunnerFigure.center ≈ horizontally centered-left within lower 60% of screen
AgentOrb.center = RunnerFigure.headAnchor
TornPaperTag.bottomLeading = safeArea.bottomLeading + spacing
ComposerPill.bottomTrailing = safeArea.bottomTrailing + spacing
HomeIndicator.bottom = safeArea.bottom
```

Fixed vs. proportional: StatusBar/DynamicIsland/HomeIndicator are OS-fixed. HeadlineTitle and Subheadline appear content-driven, left-anchored with fixed margins. RunnerFigure/AgentOrb scale proportionally with screen size (content-driven, not pixel-fixed). ComposerPill and TornPaperTag are safe-area/edge-anchored.

---

## 16. Light / Dark

No true light/dark appearance pair is present — instead there are **two brand color variants (Blue, Green)** using an inverted contrast scheme.

| Aspect | Shared | Changed |
|---|---|---|
| Layout/structure | Identical component positions and sizes | — |
| Typography | Identical styles/weights | Text/figure colors invert to maintain contrast against each background |
| Copy | "Personal Agent", "Let's make it happen.", "Composer / Start here" identical | Tag callout copy differs: "GET THINGS MOVING" (Blue) vs. "PLAN CREATE MOVE" ⚡ (Green) |
| Surfaces | Same shapes/radii | Fill colors invert (dark tag on Blue vs. light tag on Green) |
| Agent orb | Same glass-sphere treatment | Core color matches each variant's accent |

No dedicated dark-mode (as opposed to brand-color-variant) evidence exists — DARK_MODE: UNKNOWN.

---

## 17. Evidence & Confidence Summary

- **OBSERVED / MEASURED:** overall layout structure, presence/position of all listed components, the two-variant color-inversion pattern, absence of particle/ring effects on the orb, absence of a second (non-color) UI state.
- **INFERRED:** interactive affordances of MenuButton/ComposerPill, AgentOrb's semantic role as "the Agent."
- **ESTIMATED:** all HEX values, all point sizes, spacing/margins, radii.
- **UNKNOWN:** exact device model/resolution, font families, animation timing, contextual UI (settings/history sheets), safe-area exact insets, whether AgentOrb/RunnerFigure are interactive.

---

## 18. Implementation Handoff

### Components
- AppIcon
- MenuButton
- HeadlineTitle
- Subheadline
- RunnerFigure
- AgentOrb (core reusable Agent visual)
- MotionSquiggle (decorative)
- TornPaperTag
- ComposerPill

### Tokens
- Full `colors` set for both Blue and Green variants (see Section 14)
- `typography` weights/case rules for title, subhead, tag label, composer text
- `radius` set (full-pill composer, medium app icon, irregular tag)
- `surface.agentOrb.glass` flag
- `glow` and `opacity` values for AgentOrb

### States
- idle (only state evidenced)
- Additional Agent states (thinking/working/checking/result/failed) are **not evidenced** — must be confirmed with additional reference frames before implementation.

### Motion
- No animation data evidenced — TIMING_UNKNOWN for all properties. If an idle pulse/breathing motion on AgentOrb is intended, it must be confirmed separately; do not fabricate timing.

### Interaction
- tap: MenuButton (opens menu — INFERRED)
- tap: ComposerPill (opens composer/input — INFERRED)
- Unconfirmed: AppIcon tap target, RunnerFigure/AgentOrb tap target

### Unknowns (must be confirmed before implementation)
1. Exact device target resolution and safe-area insets.
2. Font family for title/subhead and for the tag's marker-style lettering.
3. Exact HEX values (current values are estimated from a compressed image).
4. Whether Blue/Green are theme variants of the same product or distinct marketing assets.
5. Whether AgentOrb has additional functional states beyond idle.
6. Interaction behavior for MenuButton, ComposerPill, and whether the hero graphic itself is tappable.
7. Presence/absence of any contextual sheets (settings, models, history) not shown in this image.
