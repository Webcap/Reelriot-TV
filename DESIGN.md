---
name: ReelRiot TV
description: The Signal Room — a bold, remote-first control room for aggregated streaming on Android TV & Tizen
colors:
  signal-red: "#EC1D24"
  canvas-black: "#000000"
  canvas-cool: "#0B0F14"
  surface-graphite: "#1A1A1A"
  warning-amber: "#F59E0B"
  success-green: "#16A34A"
  info-blue: "#3B82F6"
typography:
  display:
    fontFamily: "Roboto, sans-serif"
    fontSize: "s(72)–s(90)"
    fontWeight: 900
    lineHeight: 1.05
    letterSpacing: "normal"
  headline:
    fontFamily: "Roboto, sans-serif"
    fontSize: "s(48)–s(56)"
    fontWeight: 900
    lineHeight: 1.1
    letterSpacing: "normal"
  title:
    fontFamily: "Roboto, sans-serif"
    fontSize: "s(28)–s(32)"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "Roboto, sans-serif"
    fontSize: "s(18)–s(24)"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  label:
    fontFamily: "Roboto, sans-serif"
    fontSize: "s(12)–s(16)"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.02em"
rounded:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  pill: "32px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  2xl: "48px"
  3xl: "64px"
  4xl: "96px"
components:
  button-primary:
    backgroundColor: "{colors.signal-red}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "16px 40px"
  button-primary-focused:
    backgroundColor: "{colors.signal-red}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
  poster-card:
    backgroundColor: "{colors.surface-graphite}"
    rounded: "{rounded.md}"
  nav-rail-item-selected:
    backgroundColor: "{colors.signal-red}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
---

# Design System: ReelRiot TV

## Overview

**Creative North Star: "The Signal Room"**

ReelRiot TV is a control room, not a storefront. It sits between the viewer and a scatter of unreliable broadcast sources — multiple streaming providers, any of which might be down on a given night — and presents one confident, always-live feed. The visual language borrows from the broadcast/signal world it's actually solving for: near-black canvases like a dim control room, one alarm-red accent that reads as "live" and "select," and type that's built to be read across a room, not a desk. Nothing here is decorative; everything either orients a viewer holding a remote six feet from the screen, or tells them the system is working on their behalf.

This is a 10-foot, remote-only surface. There is no hover-as-primary-affordance, no dense information scent, no small print. Focus state *is* the cursor — a component either has D-pad focus and reads as unmistakably "here," or it recedes into the dark canvas around it.

**Key Characteristics:**
- Near-black canvas throughout; light exists only where it's earned (posters, hero art, focus states).
- One signal-red accent, used sparingly and consistently for focus, selection, and the single primary action per screen.
- Heavy type weights (900 for display/headline, bold for body/label emphasis) — built for distance reading, not desktop density.
- Depth comes from translucent white layering on black (a "glass over signal-room dark" model), not drop shadows — shadows are reserved for a handful of dramatic full-bleed poster/backdrop moments.
- Every interactive surface has an unambiguous, high-contrast D-pad focus state; nothing relies on touch or a pointer.

## Colors

The palette is small on purpose: one accent, three near-black canvases with distinct jobs, and a short semantic set for status. Color is not used to differentiate brand moments — it's used to answer "what is focused, what matters, what state is this in."

### Primary
- **Signal Red** (`#EC1D24`): The one accent. Used for D-pad focus rings, selected nav state, the primary CTA (e.g. "Play"), toggles-on, and destructive/alert emphasis. It should never appear as a passive decorative element — its presence always means "this is selected, active, or the one thing to press."

### Neutral
- **Canvas Black** (`#000000`): The default full-screen background — home, player, and most list/browse screens. True black, not a near-black gray; on TV/OLED this also reads as "the screen recedes, the content is the only thing lit."
- **Canvas Cool** (`#0B0F14`): A secondary, faintly blue-tinted near-black used specifically for detail and "cinematic" screens (title detail, sports detail, pairing) — a deliberate, slightly more atmospheric variant of the primary canvas, not a random substitute for it.
- **Surface Graphite** (`#1A1A1A`): Raised-surface background for cards and containers that need to read as "above" the canvas without using translucency (e.g. solid poster-card backgrounds before the image loads).
- **White, at translucency steps** (not a discrete swatch — see the Elevation & Depth section): the actual "surface" system is built from `Colors.white` at low alpha over the canvas, not from additional neutral hex values.

### Status (semantic, used sparingly)
- **Warning Amber** (`#F59E0B`): Caution/attention states (e.g. provider retry, outage messaging).
- **Success Green** (`#16A34A`): Confirmation states (e.g. "watched," successful pairing).
- **Info Blue** (`#3B82F6`): Neutral informational emphasis, used as a light/base/dark tonal family (`#60A5FA` / `#3B82F6` / `#2563EB` are all seen in the codebase as legitimate lighter/base/darker steps of this one role, not drift).

### Named Rules
**The One Signal Rule.** Signal Red is the only accent color with a job. If a new screen needs "an accent," it's Signal Red or it's not an accent — it's a status color (amber/green/blue) used for its specific semantic meaning, never as decoration.

**The Canonical Red Rule.** `#EC1D24` is the canonical brand red going forward. `#DC2626` and `#E60000` exist widely in the current codebase (45 and 15 occurrences respectively) doing the identical job as `#EC1D24` — this is drift, not intentional variation, and both are legacy values to migrate to `#EC1D24` on touch, not values to reach for in new work.

## Typography

**Display/Body/Label Font:** Roboto (system default; no custom font family is loaded in the project — this is the correct choice per Material/Android conventions and should stay the system face rather than introducing a custom typeface).

**Character:** Heavy and unambiguous. This is a couch-distance, remote-navigated surface — type leans on weight (900 for anything that needs to command attention, bold for anything that needs to be read quickly) far more than on size variation alone.

### Hierarchy
- **Display** (weight 900, `s(72)`–`s(90)`, line-height 1.05): Splash and hero title moments only — rare, maximum-impact use.
- **Headline** (weight 900, `s(48)`–`s(56)`, line-height 1.1): Screen and detail-page titles (movie/show title, section headers).
- **Title** (weight 700, `s(28)`–`s(32)`, line-height 1.2): Card and subsection titles, row headers.
- **Body** (weight 400, `s(18)`–`s(24)`, line-height 1.4): Descriptions, synopsis text, primary readable content. This is the single largest size cluster in the codebase — the real "reading" size for this app is closer to a desktop *headline* size than a desktop body size, because of viewing distance.
- **Label** (weight 600, `s(12)`–`s(16)`, letter-spacing 0.02em): Metadata, badges, captions, secondary chrome.

### Named Rules
**The Reading-Distance Rule.** Never reason about type size the way a web/desktop system would. `s(18)` is this system's "body copy," not a caption — the `s()` scaling function (value × current width ÷ 1920) is the only correct way to size text; a raw, unscaled font size is a bug on this surface, not a stylistic choice.

## Layout

The scaling model is a single function: `s(value) = value * currentWidth / 1920` (`ResponsiveUtils.scale`), applied to nearly every font size, radius, spacing, and icon dimension in the codebase. This is the system's actual grid — not a breakpoint set, but a continuous scale-to-current-TV-resolution model anchored at a 1920px-wide reference design. Any new UI should size everything through `s()` rather than hardcoding pixel values, or it will be visibly mis-scaled on non-1080p TV resolutions.

Navigation is a persistent left rail (`home_nav_rail.dart`) plus D-pad-focusable horizontal content rows — the standard 10-foot "rail + shelves" browse pattern, not a top nav bar or bottom tab bar (which belong to touch-first phone/tablet layouts, not this surface).

## Elevation & Depth

This system does not build depth from drop shadows. Depth is conveyed almost entirely through **translucent white layered on the near-black canvas** — a "glass over signal-room dark" model. Shadows exist (23 occurrences) but are reserved for a small number of full-bleed dramatic moments (hero backdrops, detail-page poster art) rather than general-purpose elevation.

### Surface Vocabulary (translucency steps, all `Colors.white.withValues(alpha: …)` over the canvas)
- **Whisper** (`alpha: 0.03–0.05`): Base resting surface for cards/containers — barely lifted off canvas.
- **Hover/Focus-adjacent** (`alpha: 0.08–0.15`): A surface that's being interacted with but not the primary focus target.
- **Emphasis / border** (`alpha: 0.2–0.3`): Borders, dividers, and stronger separation between a surface and the canvas behind it.

### Named Rules
**The Glass-Not-Shadow Rule.** Default to translucent white layering for elevation. Reach for a real `BoxShadow` only for full-bleed imagery moments (hero art, poster backdrops) where a shadow is doing real compositional work, not for ordinary card/container elevation.

## Shapes

Corner radius follows the same `s()`-scaled model as typography and spacing, at six steps: `s(4)` / `s(8)` / `s(12)` / `s(16)` / `s(24)` / `s(32)`. Small controls and chips sit at the low end (`xs`/`sm`); cards and containers at `md`/`lg`; hero/pill-shaped elements (large buttons, avatar frames) at `xl`/`pill`. A handful of unscaled raw radii (`12`, `8`, `6` without `s()`) exist in the codebase as legacy drift — new work should always route radius through `s()`.

## Components

Character in one phrase: **bold and immediate.** Every interactive component should be unmistakable at a glance and instantly readable at D-pad-focus distance — high-contrast focus states, heavy type, no subtle affordances a remote user could miss.

### Buttons
- **Shape:** `rounded.sm` (`8px` scaled).
- **Primary:** Signal Red background, white label text, generous horizontal padding (`16px 40px` scaled) — used for the single primary action per screen (e.g. "Play").
- **Focus:** Buttons don't have a separate hover state (no pointer) — the focused state is a scale/glow or border treatment in Signal Red; unfocused non-primary buttons sit on translucent-white surfaces, not solid fills.
- **Secondary/Ghost:** Translucent white surface (`Whisper`/`Hover` steps above), white or `white54` label text.

### Poster / Media Cards
- **Corner Style:** `rounded.md` (`12px` scaled).
- **Background:** Surface Graphite (`#1A1A1A`) before artwork loads, then the artwork itself.
- **Focus:** Scale-up + Signal Red focus ring or border on D-pad focus — this is the primary "you are here" signal while browsing a row.
- **Badges:** Small label-weight text on a Signal Red or status-color pill, upper corner of the card (quality/progress/live badges).

### Navigation Rail
- **Style:** Persistent left rail, icon + label per destination.
- **Selected state:** Signal Red icon/text on a low-alpha Signal Red translucent background (`alpha: 0.1–0.2`), not a solid red fill — the accent marks selection without overwhelming the rail.
- **Unselected:** White or `white54` icon/text on canvas, no visible container.

### Toggles / Switches
- **On:** Signal Red thumb/track.
- **Off:** `white24` — a quiet, clearly "off" translucent gray, never a second accent color.

### Stat / Info Cards (e.g. watch-time, account stats)
- **Style:** `Whisper`-level translucent white background (`alpha: 0.05`), `white10` border, `rounded.lg` (`16px` scaled) corners — icon in Signal Red, bold value text, `white54` label beneath. Purely informational, never focusable/interactive.

## Do's and Don'ts

### Do:
- **Do** size every font, radius, spacing, and icon dimension through `s()` — this is the system's actual responsive grid.
- **Do** use Signal Red (`#EC1D24`) as the only accent color, and only to mean "focused, selected, primary action, or alert."
- **Do** build elevation from translucent white layering on the canvas; reserve real shadows for full-bleed imagery moments.
- **Do** design every interactive element's D-pad-focused state first — it is the primary (often only) interaction signal on this surface.
- **Do** lean on weight (900/bold) over size for hierarchy; this is a distance-reading surface.

### Don't:
- **Don't** introduce `#DC2626` or `#E60000` in new work — they're legacy duplicates of Signal Red; migrate them to `#EC1D24` when touching a file that uses them.
- **Don't** invent a new accent color for "brand variety." Status colors (amber/green/blue) exist for specific semantic states only, not for decoration.
- **Don't** hardcode an unscaled pixel value for font size, radius, or spacing — always route through `s()`.
- **Don't** design a primary interaction around hover, touch, or pointer proximity — there is no pointer on this surface, only D-pad focus.
- **Don't** use a bottom tab bar or top nav bar pattern; navigation is the persistent left rail plus focusable content rows.
