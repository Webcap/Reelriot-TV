---
version: 1
slug: "lib-screens-home-screen-dart"
primary_target: "lib/screens/home_screen.dart"
related_targets: ["lib/widgets/home/home_top_bar.dart","lib/widgets/home/home_spotlight_tile.dart","lib/widgets/home/home_quick_tiles.dart","lib/widgets/home/home_category_tiles.dart","lib/widgets/home/home_media_row.dart","lib/widgets/home/home_continue_watching.dart","lib/widgets/home/home_genres.dart","lib/widgets/home/home_providers.dart","lib/widgets/home/home_up_next.dart","lib/widgets/home/home_hero_button.dart","lib/widgets/home/home_update_card.dart","lib/widgets/poster_card.dart","lib/theme/dashboard_theme.dart"]
---

# Home Dashboard — Surface Brief

## Scope & mode
Primary target: `lib/screens/home_screen.dart` and its `lib/widgets/home/*` sub-widgets, plus `lib/widgets/poster_card.dart`. Mode: **Operate** — a remote-only, 10-foot browse/dashboard surface.

## Audience, job, constraints
Cord-cutting viewers on Android TV / Tizen, remote-only, sitting 6-10 feet away at night. Job: sit down, find something to watch, start playback fast. Must scale via the existing `s(value) = value * width / 1920` grid; must preserve all existing functionality (discovery feed, continue watching, up next, genres, providers, ads, live event, update banner, error/empty states, resume dialogs).

## Chosen direction — structural redesign, not a reskin
Two color-only passes ("Call Board", then a "canon" retheme) were rejected as reskins — same hero-carousel-plus-shelves skeleton, same left icon rail, just different palettes. The user was explicit: they want new UI elements and a different layout, not a color change. This pass changes the actual information architecture:

- **Left icon rail → horizontal top bar** (`home_top_bar.dart`, replaces the deleted `home_nav_rail.dart`). Frees the full width for content; Left/Right now moves between tabs, Down drops into the dashboard (previously Up/Down between tabs, Right into content).
- **Full-bleed edge-to-edge hero → contained spotlight tile** (`home_spotlight_tile.dart`, replaces the deleted `home_hero_section.dart`). The featured title is the largest tile in a grid of tiles, not a backdrop the whole screen sits on.
- **New: a quick-tiles side column** (`home_quick_tiles.dart`) next to the spotlight, surfacing the top Continue Watching and Up Next (or trending fallback) items with a resume progress bar — visible without any scrolling, not buried below the fold in a shelf.
- **Pill-shaped Movies/TV switcher → two large category tiles** (`home_category_tiles.dart`, replaces the deleted `home_top_nav.dart`), sized like the rest of the dashboard's tiles rather than floating above content as an afterthought.
- Below this new top-of-screen dashboard, the existing full Continue Watching / Up Next / discovery / genres / providers rows remain (still valuable for browsing everything, not just the top item), restyled with the plain, restrained focus model built in the prior pass (`dashboard_theme.dart` — soft white lift for generic focus, Signal Red reserved for live/selected/primary-action meaning).

`_onContinueWatchingTap` / `_onUpNextTap` in `home_screen.dart` were extracted into shared methods so both the full rows and the new quick tiles drive the exact same resume/navigation logic — no duplicated behavior.

## Unresolved decisions (resolve during build/finish review)
- Quick-tile fallback priority (Continue Watching → Up Next → trending) has not been checked against every empty-state combination on-device; verify Movies-only accounts (no Up Next) and fresh accounts (no history) render sensibly.
- Top-bar Left/Right-between-tabs plus Down-into-content key handling should be checked on a real remote for any edge case Flutter's default directional focus fallback doesn't cover.
- DESIGN.md was not regenerated after this pass (no finish-review/documenter cycle ran) and still describes the earlier "Call Board" system; treat it as stale until documented fresh.
- `home_ai_recommendations.dart` and `home_airing_today.dart` remain re-themed but unwired into `home_screen.dart`'s build (pre-existing condition, out of scope).
