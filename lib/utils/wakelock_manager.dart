import 'package:wakelock_plus/wakelock_plus.dart';

/// A reference-counted wrapper around WakelockPlus.
/// This prevents race conditions during screen transitions (e.g., Navigator.pushReplacement)
/// where the new screen calls enable() before the old screen calls disable().
class WakelockManager {
  static int _refCount = 0;

  static void enable() {
    _refCount++;
    WakelockPlus.enable();
  }

  static void disable() {
    _refCount--;
    if (_refCount <= 0) {
      _refCount = 0;
      WakelockPlus.disable();
    }
  }
}
