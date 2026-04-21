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

  CaffeinePlayerSubtitlesSource({this.name, this.url, this.data});
}

class CaffeinePlayerController extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  String name = '';
  String? watchingText;

  final List<void Function(CaffeinePlayerEvent)> _listeners = [];
  final StreamController<bool> _controlsVisibilityStreamController =
      StreamController<bool>.broadcast();

  bool _isBuffering = false;
  bool _controlsVisible = false;

  CaffeinePlayerController() {
    player = Player();
    videoController = VideoController(player);
    _setupListeners();
  }

  Stream<bool> get controlsVisibilityStream =>
      _controlsVisibilityStreamController.stream;

  void _setupListeners() {
    player.stream.buffering.listen((isBuffering) {
      _isBuffering = isBuffering;
      _emit(
        isBuffering
            ? CaffeinePlayerEventType.bufferingStart
            : CaffeinePlayerEventType.bufferingEnd,
      );
    });

    player.stream.completed.listen((completed) {
      if (completed) _emit(CaffeinePlayerEventType.finished);
    });

    player.stream.error.listen((error) {
      _emit(CaffeinePlayerEventType.error, message: error);
    });

    player.stream.playing.listen((playing) {
      _emit(
        playing ? CaffeinePlayerEventType.play : CaffeinePlayerEventType.pause,
      );
    });

    player.stream.position.listen((position) {
      _emit(CaffeinePlayerEventType.progress, position: position);
    });
  }

  void _emit(
    CaffeinePlayerEventType type, {
    Duration? position,
    String? message,
  }) {
    final event = CaffeinePlayerEvent(
      type,
      position: position,
      message: message,
    );
    for (var listener in _listeners.toList()) {
      listener(event);
    }
    notifyListeners();
  }

  void addEventsListener(void Function(CaffeinePlayerEvent) listener) {
    _listeners.add(listener);
  }

  void removeEventsListener(void Function(CaffeinePlayerEvent) listener) {
    _listeners.remove(listener);
  }

  void toggleControlsVisibility(bool visible) {
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
    if (headers != null && headers.isNotEmpty) {
      final headerString = headers.entries
          .map((e) => "${e.key}: ${e.value}")
          .join("\r\n");
      (player.platform as dynamic).setProperty('http-header-fields', headerString);
    }

    if (liveStream) {
      // Stability optimizations for live streams
      (player.platform as dynamic).setProperty('demuxer-readahead-secs', '10');
      (player.platform as dynamic).setProperty('cache-secs', '15');
      (player.platform as dynamic).setProperty('hwdec', 'mediacodec');
    }

    // Handle subtitles
    if (subtitles != null && subtitles.isNotEmpty) {
      for (var sub in subtitles) {
        if (sub.url != null) {
          player.setSubtitleTrack(SubtitleTrack.uri(
            sub.url!,
            title: sub.name,
          ));
        } else if (sub.data != null) {
          player.setSubtitleTrack(SubtitleTrack.data(
            sub.data!,
            title: sub.name,
          ));
        }
      }
    }

    await player.open(
      Media(url),
      play: true,
    );
    if (startAt > Duration.zero) {
      await player.seek(startAt);
      
      StreamSubscription<Duration>? sub;
      sub = player.stream.duration.listen((d) {
        if (d > Duration.zero) {
          player.seek(startAt);
          sub?.cancel();
        }
      });
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

  void play() => player.play();
  void pause() => player.pause();
  void seekTo(Duration position) => player.seek(position);

  bool isPlaying() => player.state.playing;
  bool isBuffering() => _isBuffering;

  Duration get position => player.state.position;
  Duration get duration => player.state.duration;

  List<AudioTrack> get audioTracks => player.state.tracks.audio;
  List<SubtitleTrack> get subtitleTracks => player.state.tracks.subtitle;

  void setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  void setSubtitleTrack(SubtitleTrack track) => player.setSubtitleTrack(track);

  @override
  void dispose() {
    _controlsVisibilityStreamController.close();
    player.dispose();
    super.dispose();
  }
}
