# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Cord-cutting streaming viewers watching on Android TV devices and Samsung Tizen smart TVs, navigating entirely by remote control (D-pad, select, back, media transport keys — no touch, no pointer). They already have, or are actively pairing, a ReelRiot account created on the phone/web app; the TV app has no standalone login of its own. Their core job on this surface is: sit down, find something to watch (browse the discovery feed, search, or continue something in progress), and start playback with minimal friction.

## Product Purpose

ReelRiot TV is the smart-TV client of the ReelRiot streaming app. It lets a user discover and watch movies, TV shows, and live sports on their television, paired to their existing ReelRiot phone/web account via a pairing code. It aggregates playable streams from multiple third-party providers per title so that a working stream is very likely to be found even when individual sources are unreliable, and keeps profile, avatar, and watch-history state in sync with the user's other ReelRiot devices in real time.

## Positioning

Two mechanisms a copycat couldn't casually replicate:

- **Multi-source aggregation with failover.** Each title is resolved through a backend ("Caffeine API") against a rotating list of third-party providers (currently vidsrcsu, vidzee, vixsrc, vidfun, vidsrcme, nxsha), racing/cycling through them until one returns a playable stream. When no provider returns a directly resolvable stream, an Android-only WebView-based embedded-player fallback can still play the title by rendering the provider's own page and reporting progress back into the app's watch-history system — so "no provider worked" essentially never means "the user is stuck."
- **Companion-paired experience.** The TV app is not a separate account — it's paired to the user's existing phone/web account via a pairing code, and profile, avatar, and watch/continue-watching progress stay synced in real time (Supabase realtime + a server-computed watch-stats endpoint merged with local history) across devices.

## Operating Context

Living-room viewing, 10-foot UI, remote-only input. `TvKeys` unifies input handling across Google/Android TV remotes, Samsung Tizen Smart Remotes (via ADB/HDMI), Amazon Fire TV remotes, generic Bluetooth remotes, and physical keyboards as a fallback — there is no touch or mouse-driven interaction path on this surface.

Typical flow: home discovery feed (hero + genre/trending/social rows) → browse by category, search, genre, actor, or provider, or resume from favorites/continue-watching → title detail screen → player. Playback health is monitored by an outage service that polls backend health and surfaces an overlay during outages rather than letting individual screens fail silently.

Two build flavors exist: `dev` (`.env.dev`, local API) and `prod` (`.env.prod`, live API).

## Capabilities and Constraints

- **Auth:** pairing-code flow only (`pairing_screen.dart`); no email/password or other login path on TV.
- **Streaming:** no first-party CDN. Content is resolved via the Caffeine API backend across the provider list above. `flixhq` and `vidlink` are backend-available but not currently wired into the TV app's provider list.
- **Embedded fallback player:** Android-only (`embedded_web_player_screen.dart` + `embed_stream_resolver.dart`); Tizen has no WebView implementation available to Flutter, so this path is unavailable there and those providers simply fail over on Tizen.
- **Ads:** StartApp SDK interstitials, plus native ads served via Supabase.
- **Watch history:** Supabase-backed (`continue_watching_history`, `completed_watch_history`, `playback_history_events`), merged with the Caffeine API's own server-computed watch-time stats (max of local vs. server per media type).
- **Device targets confirmed in testing:** Android TV emulator, Chromecast with Google TV (Amlogic-based STB).

## Brand Commitments

User-facing brand name is **ReelRiot** (package id and some internal naming still reference the prior/internal name "Caffeine" — treat ReelRiot as the brand of record for user-facing work). Primary accent color observed in the existing UI is red (`#EC1D24` canonical; legacy `#DC2626`/`#E60000` are drift to migrate on touch, not values to reach for in new work).

**Standing visual direction: canon, not a themed world.** After trying a themed metaphor world (video-rental-store "Home Video") on the home dashboard and having it rejected outright, the user confirmed they want the category-standard clean/modern streaming-TV dashboard pattern — near-black canvas, hero + shelves, restrained color (neutrals plus the one red accent) — executed at high craft, not reinterpreted as a concept. Craft bar: Netflix (browse density, hero pattern) and Apple TV (restraint, typography polish, smooth focus lift). Do not propose another themed/skeuomorphic visual world for this app without being asked; default to polishing the canon pattern instead.

## Evidence on Hand

None supplied — no testimonials, case studies, press, or user metrics on hand. Future work must not fabricate any of these.

## Product Principles

1. Never leave the user stuck on a title — exhaust every provider, then the embedded-browser fallback, before admitting a stream can't be found.
2. Remote-first: every surface must be fully usable by D-pad and remote transport keys alone, with no reliance on touch or a pointer.
3. Account state (profile, avatar, watch history) always stays in sync with the user's paired phone/web account rather than being siloed to the TV.
4. Resilience over polish when they conflict: surface outages and failures gracefully (outage overlay, automatic provider retry) rather than presenting a broken or frozen screen.
5. Free, aggregated access is the core value proposition — finding *a* working stream should never be harder than it has to be.
