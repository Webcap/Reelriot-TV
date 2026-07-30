import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/material.dart';
import 'dart:async';

enum CaffeinePlayerEventType {
  initialized,
  play,
  pause,
  seek,
  bufferingStart,
  bufferingEnd,
  finished,
  error,
  controlsVisible,
  controlsHiddenStart,
  controlsHiddenEnd,
  progress,
}

class CaffeinePlayerEvent {
  final CaffeinePlayerEventType type;
  final Duration? position;
  final String? message;

  CaffeinePlayerEvent(this.type, {this.position, this.message});
}

class CaffeinePlayerSubtitlesSource {
  final String? name;
  final String? url;
  final String? data;
  final bool isDefault;

  CaffeinePlayerSubtitlesSource({
    this.name,
    this.url,
    this.data,
    this.isDefault = false,
  });
}

class CaffeinePlayerController extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  String name = '';
  String? watchingText;

  final List<void Function(CaffeinePlayerEvent)> _listeners = [];
  final List<StreamSubscription> _subscriptions = [];
  final StreamController<bool> _controlsVisibilityStreamController =
      StreamController<bool>.broadcast();

  bool _isBuffering = false;
  bool _controlsVisible = false;
  bool _isDisposed = false;
  bool _isLiveStream = false;
  Duration? _lastEmittedPosition;

  CaffeinePlayerController() {
    player = Player();
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'mediacodec-copy', // Hardware decoding via mediacodec-copy for maximum stability and zero SELinux/BufferPool stalls
      ),
    );
    _setupListeners();
  }

  Stream<bool> get controlsVisibilityStream =>
      _controlsVisibilityStreamController.stream;

  bool get isLiveStream => _isLiveStream;

  void _setupListeners() {
    _subscriptions.add(player.stream.buffering.listen((isBuffering) {
      if (_isDisposed) return;
      _isBuffering = isBuffering;
      _emit(
        isBuffering
            ? CaffeinePlayerEventType.bufferingStart
            : CaffeinePlayerEventType.bufferingEnd,
      );
    }));

    _subscriptions.add(player.stream.completed.listen((completed) {
      if (_isDisposed) return;
      if (completed) _emit(CaffeinePlayerEventType.finished);
    }));

    _subscriptions.add(player.stream.error.listen((error) {
      if (_isDisposed) return;
      _emit(CaffeinePlayerEventType.error, message: error);
    }));

    _subscriptions.add(player.stream.playing.listen((playing) {
      if (_isDisposed) return;
      _emit(
        playing ? CaffeinePlayerEventType.play : CaffeinePlayerEventType.pause,
      );
    }));

    _subscriptions.add(player.stream.position.listen((position) {
      if (_isDisposed) return;
      // Throttle position progress notifications to 1Hz (per second change)
      // to eliminate UI rebuild microtask queueing and input lag when pausing.
      if (_lastEmittedPosition == null ||
          position.inSeconds != _lastEmittedPosition!.inSeconds) {
        _lastEmittedPosition = position;
        _emit(CaffeinePlayerEventType.progress, position: position);
      }
    }));
  }

  void _emit(
    CaffeinePlayerEventType type, {
    Duration? position,
    String? message,
  }) {
    if (_isDisposed) return;
    
    if (type != CaffeinePlayerEventType.progress) {
      debugPrint('[CaffeinePlayerController] 📢 Emitting event: $type');
    }

    final event = CaffeinePlayerEvent(
      type,
      position: position,
      message: message,
    );
    for (var listener in _listeners.toList()) {
      listener(event);
    }
    
    // Safety check again before notifyListeners
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void addEventsListener(void Function(CaffeinePlayerEvent) listener) {
    _listeners.add(listener);
  }

  void removeEventsListener(void Function(CaffeinePlayerEvent) listener) {
    _listeners.remove(listener);
  }

  void toggleControlsVisibility(bool visible) {
    if (_isDisposed) return;
    _controlsVisible = visible;
    _controlsVisibilityStreamController.add(visible);
    _emit(
      visible
          ? CaffeinePlayerEventType.controlsVisible
          : CaffeinePlayerEventType.controlsHiddenEnd,
    );
  }

  Future<void> setDataSource(
    String url, {
    Map<String, String>? headers,
    bool liveStream = false,
    Duration startAt = Duration.zero,
    List<CaffeinePlayerSubtitlesSource>? subtitles,
  }) async {
    if (_isDisposed) return;
    
    // Clear old subscriptions to avoid listener leaks (important for provider retries)
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _isLiveStream = liveStream;
    notifyListeners();

    
    // Standard headers for all requests
    final Map<String, String> defaultHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    // Final merged headers for the request
    Map<String, String> merged = {...defaultHeaders};
    if (headers != null) {
      merged.addAll(headers);
    }

    // Performance and RAM optimizations for TV boxes (Amlogic/Mali/Adreno)
    (player.platform as dynamic).setProperty('vd-lavc-dr', 'no'); // MUST be 'no' on Android to prevent SELinux dmabuf AVC denials
    (player.platform as dynamic).setProperty('hwdec', 'mediacodec-copy'); // Avoid zero-copy dmabuf bufferpool pipeline drops
    (player.platform as dynamic).setProperty('cache', 'yes');
    
    // Low-latency and decoder sync optimizations to prevent frozen video
    (player.platform as dynamic).setProperty('video-sync', 'audio');
    (player.platform as dynamic).setProperty('framedrop', 'decoder'); // Drop late frames at decoder level, not VO stage
    
    // Force seekable to true for better HLS/Proxy support
    (player.platform as dynamic).setProperty('force-seekable', 'yes');
    
    // HLS specific optimizations
    (player.platform as dynamic).setProperty('hls-bitrate', '5000000'); // Cap at 5Mbps for stability
    (player.platform as dynamic).setProperty('cache-pause-initial', 'yes');
    (player.platform as dynamic).setProperty('stream-buffer-size', '8192k');

    // Set initial start position via mpv property (most robust way)
    if (startAt > Duration.zero) {
      // mpv 'start' property accepts seconds or HH:MM:SS
      (player.platform as dynamic).setProperty('start', '${startAt.inSeconds}');
    } else {
      (player.platform as dynamic).setProperty('start', '0');
    }

    if (liveStream) {
      // Buffer settings for live streams (32MB max to prevent RAM exhaustion on Android TV)
      (player.platform as dynamic).setProperty('demuxer-max-bytes', '32M');
      (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '8M');
      (player.platform as dynamic).setProperty('demuxer-readahead-secs', '20');
      (player.platform as dynamic).setProperty('cache-secs', '30');
    } else {
      // Buffer settings for regular media (64MB forward buffer + 16MB back buffer)
      // Prevents native RAM OOM crash / video freeze on low-memory Android TV devices.
      (player.platform as dynamic).setProperty('demuxer-max-bytes', '64M');
      (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '16M');
    }

    await player.open(
      Media(
        url,
        httpHeaders: merged,
      ),
      play: true,
    );

    // Handle subtitles (AFTER player.open so tracks are preserved)
    if (subtitles != null && subtitles.isNotEmpty) {
      SubtitleTrack? defaultTrack;

      for (var sub in subtitles) {
        final track = sub.url != null
            ? SubtitleTrack.uri(sub.url!, title: sub.name)
            : SubtitleTrack.data(sub.data!, title: sub.name);

        if (sub.isDefault) {
          defaultTrack = track;
        }
      }

      if (defaultTrack != null) {
        player.setSubtitleTrack(defaultTrack);
      }
    }
    
    if (startAt > Duration.zero) {
      debugPrint('[CaffeinePlayer] ⏩ Applying startup seek: $startAt');
      
      // 1. First attempt: Standard seek immediately after open
      player.seek(startAt);
      
      // 2. Second attempt: Wait for duration to be known (most reliable for HLS)
      StreamSubscription<Duration>? sub;
      sub = player.stream.duration.listen((d) {
        // Only trigger when duration is valid and significantly positive
        if (d.inSeconds > 1) {
          debugPrint('[CaffeinePlayer] ⏳ Duration confirmed ($d). Re-applying seek to $startAt');
          player.seek(startAt);
          sub?.cancel();
        }
      });
      _subscriptions.add(sub);

      // 3. Third attempt: Small delay as a safety net for slow decoders
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!_isDisposed) {
          player.seek(startAt);
        }
      });
    }

    // Wait for the player to actually have a valid video resolution before emitting initialized.
    // This ensures the loading spinner doesn't fade to a black screen.
    StreamSubscription<int?>? widthSub;
    widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0 && !_isDisposed) {
        debugPrint('[CaffeinePlayerController] 📺 Video resolution confirmed: $w x ${player.state.height}');
        _emit(CaffeinePlayerEventType.initialized);
        widthSub?.cancel();
      }
    });
    _subscriptions.add(widthSub);

    // Watchdog for initialization
    Future.delayed(const Duration(seconds: 15), () {
      if (!_isDisposed && player.state.width == 0) {
        debugPrint('[CaffeinePlayerController] ⚠️ Initialization watchdog timeout (15s). No video dimensions detected.');
        _emit(CaffeinePlayerEventType.error, message: 'Source timed out or hardware decoder stalled.');
      }
    });
  }

  // Bridge for legacy code
  Future<void> setupDataSource(dynamic dataSource) async {
    // Legacy bridge: try to extract URL if it's a BetterPlayerDataSource (even if type is missing)
    try {
      final url = (dataSource as dynamic).url as String;
      return setDataSource(url);
    } catch (e) {
      debugPrint('[CaffeinePlayerController] ⚠️ setupDataSource failed: $e');
    }
  }

  void play() {
    if (_isDisposed) return;
    player.play();
  }

  void pause() {
    if (_isDisposed) return;
    player.pause();
  }

  void seekTo(Duration position) {
    if (_isDisposed) return;
    player.seek(position);
  }

  bool isPlaying() => _isDisposed ? false : player.state.playing;
  bool isBuffering() => _isBuffering;

  Duration get position => _isDisposed ? Duration.zero : player.state.position;
  Duration get duration => _isDisposed ? Duration.zero : player.state.duration;

  List<AudioTrack> get audioTracks => _isDisposed ? [] : player.state.tracks.audio;
  List<SubtitleTrack> get subtitleTracks => _isDisposed ? [] : player.state.tracks.subtitle;

  void setAudioTrack(AudioTrack track) {
    if (_isDisposed) return;
    player.setAudioTrack(track);
  }

  void setSubtitleTrack(SubtitleTrack track) {
    if (_isDisposed) return;
    player.setSubtitleTrack(track);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    _listeners.clear();
    _controlsVisibilityStreamController.close();
    player.dispose();
    super.dispose();
  }
}

