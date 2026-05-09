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

  CaffeinePlayerController() {
    player = Player();
    videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'no', // Software decoding is much more stable on Chromecast/Amlogic
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
      _emit(CaffeinePlayerEventType.progress, position: position);
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
    _isLiveStream = liveStream;
    notifyListeners();

    
    // Standard headers for all requests
    final Map<String, String> defaultHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Chromecast Build/UTTC.250917.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    // Final merged headers for the request
    Map<String, String> merged = {...defaultHeaders};
    if (headers != null) {
      merged.addAll(headers);
    }

    // Performance optimizations for TV boxes (Amlogic/Mali)
    (player.platform as dynamic).setProperty('vd-lavc-dr', 'no'); // Keep direct rendering disabled for SELinux safety
    (player.platform as dynamic).setProperty('cache', 'yes');
    
    // Low-latency and sync optimizations for Chromecast/Mali
    (player.platform as dynamic).setProperty('video-sync', 'audio');
    (player.platform as dynamic).setProperty('framedrop', 'vo');
    
    // Force seekable to true for better HLS/Proxy support
    (player.platform as dynamic).setProperty('force-seekable', 'yes');
    (player.platform as dynamic).setProperty('demuxer-max-bytes', '128000000'); // 128MB
    (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '64000000'); // 64MB
    
    // HLS specific optimizations
    (player.platform as dynamic).setProperty('hls-bitrate', '5000000'); // Cap at 5Mbps for stability
    (player.platform as dynamic).setProperty('cache-pause', 'yes');
    (player.platform as dynamic).setProperty('stream-buffer-size', '8192k');

    if (liveStream) {
      // Stability optimizations for live streams
      (player.platform as dynamic).setProperty('demuxer-readahead-secs', '45'); // Further increase readahead
      (player.platform as dynamic).setProperty('cache-secs', '60'); // Further increase cache
    } else {
      // Buffer settings for regular media
      (player.platform as dynamic).setProperty('demuxer-max-bytes', '512M');
      (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '256M');
    }

    // Handle subtitles
    if (subtitles != null && subtitles.isNotEmpty) {
      CaffeinePlayerSubtitlesSource? defaultSub;
      
      for (var sub in subtitles) {
        final track = sub.url != null 
            ? SubtitleTrack.uri(sub.url!, title: sub.name)
            : SubtitleTrack.data(sub.data!, title: sub.name);
            
        player.setSubtitleTrack(track);
        if (sub.isDefault) {
          defaultSub = sub;
        }
      }
      
      // If no default was found, turn off subtitles (prevents last one from staying on)
      if (defaultSub == null) {
        player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        // Re-select the default one to be sure (since the loop above selects each one)
        final track = defaultSub.url != null
            ? SubtitleTrack.uri(defaultSub.url!, title: defaultSub.name)
            : SubtitleTrack.data(defaultSub.data!, title: defaultSub.name);
        player.setSubtitleTrack(track);
      }
    }

    await player.open(
      Media(
        url,
        httpHeaders: merged,
      ),
      play: true,
    );
    
    if (startAt > Duration.zero) {
      debugPrint('[CaffeinePlayer] ⏩ Seeking to start position: $startAt');
      
      // Attempt immediate seek
      await player.seek(startAt);
      
      // Also set up a listener to re-apply seek once metadata/duration is known
      StreamSubscription<Duration>? sub;
      sub = player.stream.duration.listen((d) {
        if (d > Duration.zero) {
          debugPrint('[CaffeinePlayer] ⏳ Metadata loaded (Duration: $d). Re-applying seek to $startAt');
          player.seek(startAt);
          sub?.cancel();
        }
      });
      _subscriptions.add(sub);
    }

    _emit(CaffeinePlayerEventType.initialized);
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

