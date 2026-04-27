import 'package:flutter/services.dart';

/// Centralized TV remote key matching utility.
///
/// Different TV remotes send different key codes for the same action.
/// This helper provides consistent matching across:
/// - Google/Android TV remotes
/// - Samsung Smart TV (Tizen) remotes via ADB/HDMI
/// - Amazon Fire TV remotes
/// - Generic Bluetooth remotes
/// - Physical keyboards
class TvKeys {
  TvKeys._();

  // ── Confirm / Select ────────────────────────────────────────────────────────

  /// True for Enter, Select (D-pad center), numpad Enter, Space, and Game Button A.
  static bool isSelect(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.gameButtonStart;
  }

  // ── Directional ─────────────────────────────────────────────────────────────

  static bool isUp(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp;

  static bool isDown(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowDown;

  static bool isLeft(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft;

  static bool isRight(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowRight;

  static bool isDirectional(LogicalKeyboardKey key) =>
      isUp(key) || isDown(key) || isLeft(key) || isRight(key);

  static bool isNavigation(LogicalKeyboardKey key) =>
      isDirectional(key) || isSelect(key);

  // ── Back / Exit ─────────────────────────────────────────────────────────────

  /// True for Escape, GoBack, BrowserBack (Samsung).
  static bool isBack(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack;
  }

  // ── Media Controls ──────────────────────────────────────────────────────────

  /// True for media play/pause toggle keys.
  static bool isPlayPause(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.pause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause;
  }

  static bool isMediaPlay(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaPlay ||
      key == LogicalKeyboardKey.mediaPlayPause;

  static bool isMediaPause(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaPause ||
      key == LogicalKeyboardKey.mediaPlayPause;

  static bool isMediaFastForward(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaFastForward;

  static bool isMediaRewind(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaRewind;

  static bool isMediaStop(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaStop;

  static bool isMediaSkipForward(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaTrackNext;

  static bool isMediaSkipBackward(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaTrackPrevious;

  /// Galaxy / Smart Remote "Search" button.
  static bool isSearch(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.browserSearch;
}
