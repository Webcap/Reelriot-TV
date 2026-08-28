# ReelRiot TV - TODO List

## Embedded Web Player Fallback (EmbeddedWebPlayerScreen)

- [ ] **Next Episode auto-advance**:
  - `video_loader_screen.dart`'s embedded-player fallback push (used when no provider returns a directly playable stream, Android only) is a dead-end: it doesn't inspect any result from `EmbeddedWebPlayerScreen` the way the native-player branch does for next-episode handling.
  - Wire it up to mirror the native flow: on completion, offer/auto-play the next episode for TV shows instead of just closing back to the loader.
