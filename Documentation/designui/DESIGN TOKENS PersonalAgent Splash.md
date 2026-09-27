# DESIGN_TOKENS_PersonalAgent_Splash

> Note on inputs: `Documentation/designui/README.md` was not found in this environment (no repository checkout is available here), so no DesignUI-specific standard could be applied beyond what is already stated in the source Design Data. This document is derived solely from `DESIGN_DATA_PersonalAgent_Splash.md`. If your DesignUI README defines a required naming convention, unit system, or token schema that differs from the below, re-run this conversion with that file available.

---

## 1. Token Identity

| Field | Value |
|---|---|
| Token set name | PersonalAgent_Splash |
| Source Design Data | DESIGN_DATA_PersonalAgent_Splash.md |
| Design Data confidence level | MEDIUM (single static composite image, 2 color variants) |
| Platform scope | Platform-neutral, with iOS-specific layout notes flagged explicitly |
| Variants covered | `blue`, `green` (brand color variants, not light/dark) |

---

## 2. Source Design Data

- Document: `DESIGN_DATA_PersonalAgent_Splash.md`
- Sections consumed: 2 (Canvas), 5 (Color Data), 6 (Typography), 7 (Surface Data), 8 (Agent/Living Element), 9 (State Model), 10 (Motion Data), 14 (Design Tokens draft), 15 (Responsive Rules), 16 (Light/Dark).
- No values below were introduced beyond what that document records; where that document already marked a value ESTIMATED or UNKNOWN, this document preserves that marking.

---

## 3. Color Tokens

### Global

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| color.background.primary.blue | #1B2FE0 | hex | Screen background, blue variant | Design Data §5 Variant A | ESTIMATED | Read from compressed image, not color-picked from source assets |
| color.background.primary.green | #1FE08A | hex | Screen background, green variant | Design Data §5 Variant B | ESTIMATED | Same caveat |
| color.text.onBackground.primary.blue | #FFFFFF | hex | Headline title, blue variant | Design Data §5 | ESTIMATED | |
| color.text.onBackground.primary.green | #0A0A0A | hex | Headline title, green variant | Design Data §5 | ESTIMATED | |
| color.text.onBackground.secondary.blue | #0A0A1E | hex | Subheadline, blue variant | Design Data §5 | ESTIMATED | |
| color.text.onBackground.secondary.green | #FFFFFF | hex | Subheadline, green variant | Design Data §5 | ESTIMATED | |
| color.figure.fill.blue | #FFFFFF | hex | RunnerFigure silhouette, blue variant | Design Data §5, §3 | ESTIMATED | |
| color.figure.fill.green | #0A0A0A | hex | RunnerFigure silhouette, green variant | Design Data §5, §3 | ESTIMATED | |
| color.tag.background.blue | #0A0A0A | hex | TornPaperTag surface, blue variant | Design Data §5 | ESTIMATED | |
| color.tag.background.green | #FFFFFF | hex | TornPaperTag surface, green variant | Design Data §5 | ESTIMATED | |
| color.tag.text.blue | #FFFFFF | hex | TornPaperTag text, blue variant | Design Data §5 | ESTIMATED | |
| color.tag.text.green | #0A0A0A | hex | TornPaperTag text, green variant | Design Data §5 | ESTIMATED | |
| color.composer.background.blue | #0A0A2E | hex | ComposerPill surface, blue variant | Design Data §5 | ESTIMATED | |
| color.composer.background.green | #0A0A0A | hex | ComposerPill surface, green variant | Design Data §5 | ESTIMATED | |
| color.composer.text | #FFFFFF | hex | ComposerPill text/icons, both variants | Design Data §5 | ESTIMATED | Identical across variants |

### Component-level (Agent)

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| agent.orb.fill.blue | #2A3FE8 | hex | AgentOrb core color, blue variant | Design Data §5, §8 | ESTIMATED | Matches background accent per Design Data |
| agent.orb.fill.green | #1FA860 | hex | AgentOrb core color, green variant | Design Data §5, §8 | ESTIMATED | |
| agent.orb.iconAccent (composer sparkle) | matches `agent.orb.fill.*` per variant | hex | Sparkle icon accent inside ComposerPill | Design Data §5 | ESTIMATED | Same value family as orb fill per variant; kept as one token reference rather than a duplicate to avoid two names for one semantic value |

---

## 4. Typography Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| typography.title.size | 56–64 (range, unresolved) | pt-equivalent | HeadlineTitle "Personal Agent" | Design Data §6 | ESTIMATED | Range kept as-is; single value not resolvable from a static image |
| typography.title.weight | 900 (Black/Heavy) | font-weight | HeadlineTitle | Design Data §6 | MEDIUM | |
| typography.title.lineHeight | tight (~0.9) | ratio | HeadlineTitle | Design Data §6 | ESTIMATED | |
| typography.title.family | UNKNOWN | — | HeadlineTitle | Design Data §6 | LOW/UNKNOWN | Font family not identifiable; do not substitute a guessed family |
| typography.subhead.size | 26–30 (range, unresolved) | pt-equivalent | Subheadline "Let's make it happen." | Design Data §6 | ESTIMATED | |
| typography.subhead.weight | 700 (Bold) | font-weight | Subheadline | Design Data §6 | MEDIUM | |
| typography.subhead.family | UNKNOWN (same as title) | — | Subheadline | Design Data §6 | LOW/UNKNOWN | |
| typography.tagLabel.size | 18–22 (range, unresolved) | pt-equivalent | TornPaperTag text | Design Data §6 | ESTIMATED | |
| typography.tagLabel.weight | bold, uppercase | font-weight/case | TornPaperTag text | Design Data §6 | MEDIUM | |
| typography.tagLabel.family | UNKNOWN — distinct hand-lettered/marker display face | — | TornPaperTag text | Design Data §6 | LOW/UNKNOWN | Visually distinct from title/subhead family |
| typography.composerTitle.size | ~14 | pt-equivalent | "Composer" label | Design Data §6 | ESTIMATED | |
| typography.composerTitle.weight | 600–700 | font-weight | "Composer" label | Design Data §6 | ESTIMATED | |
| typography.composerSubtitle.size | ~12 | pt-equivalent | "Start here" label | Design Data §6 | ESTIMATED | |
| typography.composerSubtitle.weight | 400–500 | font-weight | "Start here" label | Design Data §6 | ESTIMATED | |

---

## 5. Spacing Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| spacing.* | UNKNOWN | — | Margins/gaps between chrome, headline, hero graphic, tag, composer pill | Design Data §2, §3, §15 | UNKNOWN | Design Data recorded no measurable grid; only relational ordering exists (see §15 Responsive Tokens). Do not fabricate a spacing scale not evidenced. |

---

## 6. Sizing Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| sizing.agentOrb.diameter | ESTIMATED_LARGE_RELATIVE_TO_FIGURE_NECK (~1.4–1.6× figure neck width) | relative ratio | AgentOrb size | Design Data §8 | ESTIMATED | No absolute px value supported; kept as a ratio, not a coordinate |
| sizing.appIcon | medium (app-icon-scale) | relative | AppIcon tile | Design Data §3 | ESTIMATED | |
| sizing.menuButton | small (icon-button-scale) | relative | MenuButton | Design Data §3 | ESTIMATED | |
| sizing.composerPill.height | UNKNOWN | — | ComposerPill | Design Data §3, §7 | UNKNOWN | No absolute measurement supported |
| sizing.runnerFigure | large / dominant (occupies majority of lower 50–60% of screen) | relative | RunnerFigure | Design Data §3, §4 | ESTIMATED | |

---

## 7. Radius Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| radius.appIcon | medium | qualitative | AppIcon corner rounding | Design Data §7 | ESTIMATED | No px value supported |
| radius.composerPill | full (pill) | qualitative | ComposerPill shape | Design Data §7 | MEASURED (shape category), ESTIMATED (exact value) | |
| radius.tag | irregular / torn-edge (non-uniform) | qualitative | TornPaperTag shape | Design Data §7 | MEASURED (shape category) | Not a standard corner-radius; shape is a hand-cut silhouette, not a rounded rectangle |
| radius.agentOrb | full (circular/spherical) | qualitative | AgentOrb shape | Design Data §7, §8 | MEASURED | |

---

## 8. Surface Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| surface.agentOrb.glass | true (boolean) | flag | Glossy/translucent glass treatment | Design Data §7, §8 | MEASURED | Includes rim highlight and glass refraction look |
| surface.appIcon.style | flat solid | qualitative | AppIcon fill style | Design Data §7 | ESTIMATED | |
| surface.menuButton.style | transparent with thin stroke outline | qualitative | MenuButton fill/border style | Design Data §7 | MEASURED | |
| surface.composerPill.style | flat solid, dark fill | qualitative | ComposerPill fill style | Design Data §7 | MEASURED (per-variant color) | |
| surface.tag.style | flat solid, torn-edge silhouette | qualitative | TornPaperTag fill style | Design Data §7 | MEASURED | |
| surface.runnerFigure.style | flat solid illustrative silhouette | qualitative | RunnerFigure fill style | Design Data §7 | MEASURED | |

---

## 9. Shadow Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| shadow.agentOrb | soft drop shadow beneath sphere | qualitative | AgentOrb grounding shadow | Design Data §7 | ESTIMATED (INFERRED in source) | |
| shadow.composerPill | soft drop shadow | qualitative | ComposerPill elevation cue | Design Data §7 | ESTIMATED (INFERRED in source) | |
| shadow.tag | soft drop shadow | qualitative | TornPaperTag elevation cue | Design Data §7 | ESTIMATED (INFERRED in source) | |
| shadow.appIcon | subtle drop shadow | qualitative | AppIcon elevation cue | Design Data §7 | ESTIMATED (INFERRED in source) | |

No numeric shadow values (blur radius, offset, opacity) are supported by the source — kept qualitative only.

---

## 10. Glow Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| agent.orb.glow.radius | small | qualitative | AgentOrb highlight extent | Design Data §8 | ESTIMATED | Not a large emissive halo |
| agent.orb.glow.intensity | low–medium | qualitative | AgentOrb highlight strength | Design Data §8 | ESTIMATED | Primarily a glass specular highlight, not emissive glow |
| agent.orb.glow.outerRings | none | boolean/absence | AgentOrb — no rings present | Design Data §8 | OBSERVED (absence) | Do not add rings in implementation |
| agent.orb.glow.particles | none | boolean/absence | AgentOrb — no particle effects present | Design Data §8 | OBSERVED (absence) | Do not add particles in implementation |

---

## 11. Motion Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| motion.agentOrb.idlePulse | TIMING_UNKNOWN | — | Any idle breathing/pulse animation | Design Data §10 | UNKNOWN | Not evidenced by a static image; must not be fabricated |
| motion.motionSquiggle | static_decorative_only | flag | MotionSquiggle graphic | Design Data §10 | OBSERVED | Illustrative speed cue, not an actual animation |
| motion.state.thinking / working / checking / result / failed | TIMING_UNKNOWN / STATE_UNKNOWN | — | Any state-based Agent motion | Design Data §9, §10 | UNKNOWN | No frames evidencing these states exist in source Design Data |

---

## 12. Opacity Tokens

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| agent.orb.opacity | ~0.9 | 0–1 | AgentOrb fill translucency | Design Data §5, §8 | ESTIMATED | |
| composer.text.subtitle.opacity | slightly reduced (exact value UNKNOWN) | 0–1 | "Start here" secondary text | Design Data §6 | ESTIMATED/UNKNOWN | Source notes reduced opacity qualitatively only |

---

## 13. Component Tokens

Component tokens reference global tokens rather than restate values.

### AgentOrb
| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| agent.orb.size | → `sizing.agentOrb.diameter` | ref | Orb size | Design Data §8 | ESTIMATED | |
| agent.orb.fill | → `agent.orb.fill.blue` / `agent.orb.fill.green` (variant-selected) | ref | Orb core color | Design Data §5, §8 | ESTIMATED | |
| agent.orb.opacity | → `opacity.agent.orb.opacity` (§12) | ref | Orb translucency | Design Data §8 | ESTIMATED | |
| agent.orb.glow | → `agent.orb.glow.*` (§10) | ref | Orb highlight | Design Data §8 | ESTIMATED | |
| agent.orb.surface | → `surface.agentOrb.glass` | ref | Glass treatment | Design Data §7 | MEASURED | |
| agent.orb.shadow | → `shadow.agentOrb` | ref | Grounding shadow | Design Data §7 | ESTIMATED | |

### ComposerPill
| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| composer.background | → `color.composer.background.blue` / `.green` | ref | Pill fill | Design Data §5 | ESTIMATED | |
| composer.text.color | → `color.composer.text` | ref | Text/icon color | Design Data §5 | ESTIMATED | |
| composer.radius | → `radius.composerPill` | ref | Pill shape | Design Data §7 | ESTIMATED | |
| composer.shadow | → `shadow.composerPill` | ref | Elevation cue | Design Data §7 | ESTIMATED | |
| composer.iconAccent | → `agent.orb.iconAccent` | ref | Sparkle icon color | Design Data §5 | ESTIMATED | Deliberately reuses the orb-accent token rather than introducing a duplicate |

### TornPaperTag
| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| tag.background | → `color.tag.background.blue` / `.green` | ref | Tag fill | Design Data §5 | ESTIMATED | |
| tag.text.color | → `color.tag.text.blue` / `.green` | ref | Tag text color | Design Data §5 | ESTIMATED | |
| tag.radius | → `radius.tag` | ref | Torn-edge shape | Design Data §7 | MEASURED | |
| tag.shadow | → `shadow.tag` | ref | Elevation cue | Design Data §7 | ESTIMATED | |
| tag.typography | → `typography.tagLabel.*` | ref | Text style | Design Data §6 | MEDIUM/UNKNOWN | |

---

## 14. State Tokens

Only the `idle` state is documented in the source Design Data.

| name | value | unit | semantic_role | source | confidence | notes |
|---|---|---|---|---|---|---|
| agent.state.idle | default/current visual (both color variants) | state | Baseline Agent presentation | Design Data §9 | OBSERVED | The only state with visual evidence |
| agent.state.thinking | UNKNOWN | state | — | Design Data §9 | UNKNOWN | Not evidenced; must not be defined until reference frames exist |
| agent.state.working | UNKNOWN | state | — | Design Data §9 | UNKNOWN | Same |
| agent.state.checking | UNKNOWN | state | — | Design Data §9 | UNKNOWN | Same |
| agent.state.result | UNKNOWN | state | — | Design Data §9 | UNKNOWN | Same |
| agent.state.failed | UNKNOWN | state | — | Design Data §9 | UNKNOWN | Same |

---

## 15. Responsive Tokens

Expressed as relationships, per Design Data §15 — no screenshot coordinates are carried forward.

```
layout.appIcon.anchor            = safeArea.topLeading + spacing.UNKNOWN
layout.menuButton.anchor         = safeArea.topTrailing + spacing.UNKNOWN
layout.headlineTitle.anchor      = below(topChromeRow) + spacing.UNKNOWN
layout.subheadline.anchor        = below(headlineTitle) + spacing.UNKNOWN
layout.runnerFigure.anchor       = centered-left, lower ~60% of screen (content-driven, proportional)
layout.agentOrb.anchor           = runnerFigure.headAnchor (relative to figure, not absolute)
layout.tornPaperTag.anchor       = safeArea.bottomLeading + spacing.UNKNOWN
layout.composerPill.anchor       = safeArea.bottomTrailing + spacing.UNKNOWN
layout.homeIndicator.anchor      = safeArea.bottom
```

Fixed: status bar / dynamic island / home indicator (OS-owned).
Proportional/content-driven: RunnerFigure, AgentOrb.
Edge/safe-area-anchored: AppIcon, MenuButton, TornPaperTag, ComposerPill.

---

## 16. Unknown / Estimated Values

Carried forward unchanged from Design Data, not resolved here:

- Exact device resolution and safe-area insets (UNKNOWN)
- Font families for title/subhead and tag label (UNKNOWN)
- All exact HEX values (ESTIMATED — read from a compressed image, not source assets)
- All exact spacing/margin values (UNKNOWN — no grid evidence)
- All exact sizing values in absolute units (UNKNOWN — only relative/qualitative sizing supported)
- All motion timing/easing (TIMING_UNKNOWN)
- Agent states beyond `idle` (UNKNOWN — no evidence)
- Interactivity of AppIcon, RunnerFigure/AgentOrb (UNKNOWN)
- Contextual UI (settings/history/models sheets) — not evidenced at all (UNKNOWN)

---

## 17. Evidence & Confidence

| Category | Overall confidence | Basis |
|---|---|---|
| Color values | ESTIMATED | Single compressed image, no source-asset color picks |
| Typography | LOW–MEDIUM | Weight/case/relative size inferred; family UNKNOWN |
| Spacing | UNKNOWN | No measurable grid in source |
| Sizing/Radius | ESTIMATED (qualitative) | Relative/shape-category only, no absolute measurements |
| Surface/Shadow | ESTIMATED (INFERRED in source) | Visual read of flat fills and soft shadows |
| Glow | ESTIMATED | Qualitative read of a glass highlight, not an emissive glow |
| Motion | UNKNOWN | No animation frames supplied |
| States | OBSERVED (idle only) | Only one functional state shown |

No token in this document upgrades a source confidence level; several are intentionally left qualitative or UNKNOWN rather than assigned a fabricated number.

---

## 18. Native Implementation Handoff

This document stops at the token layer. For the next pipeline step (Design Tokens → Native Components → SwiftUI), an implementing agent should note:

- **Ready to consume:** color tokens (per variant), shape/radius categories, surface/glass flag for AgentOrb, glow absence-of-rings/particles, state model (idle only), responsive anchor relationships.
- **Must be resolved before implementation:** exact numeric spacing/sizing/radius values, font families, any animation timing, and whether additional Agent states are in scope.
- **Do not implement yet:** `agent.state.thinking/working/checking/result/failed` — these have no token values because they have no evidence; implementing them now would mean inventing design decisions outside this pipeline step's authority.
