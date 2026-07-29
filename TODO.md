# ReelRiot TV - TODO List

## WatchFreeStreams (wfs.lol) Support

- [ ] **Stream Source Parser**:
  - Update TV stream response model to parse `wfs` (`WatchFreeStreams`) server entries from `caffeine-api`.
  - Handle non-M3U8 embed streams (`isM3U8: false`).

- [ ] **Android TV / Fire TV Webview Player**:
  - Implement TV-optimized WebView wrapper for `https://wfs.lol/embed/...`.
  - Enable D-Pad remote navigation, auto-fullscreen, and play/pause button event forwarding for TV remotes.

- [ ] **Popunder / Redirect Guard**:
  - Suppress new window / tab popunder requests in WebView on TV devices to keep focus on the main video container.

- [ ] **TV Source Selection Overlay**:
  - Add "WatchFreeStreams" badge and 1080p label in the D-Pad focusable stream source selector dialog.
