import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/widgets/player_settings_overlay.dart';
import 'package:caffeine_tv/widgets/tv_player_controls.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key, 
    required this.url, 
    required this.title,
    required this.item,
    required this.isMovie,
    this.season,
    this.episode,
    this.episodeName,
    this.startPosition,
  });

  final String url;
  final String title;
  final dynamic item;
  final bool isMovie;
  final int? season;
  final int? episode;
  final String? episodeName;
  final Duration? startPosition;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late BetterPlayerController _controller;
  final WatchHistoryService _historyService = WatchHistoryService();
  final FocusNode _mainFocusNode = FocusNode();
  Timer? _saveTimer;
  bool _controlsVisible = false;
  StreamSubscription? _visibilitySubscription;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _setupController();
    _startProgressTimer();
    
    _visibilitySubscription = _controller.controlsVisibilityStream.listen((visible) {
      if (mounted) setState(() => _controlsVisible = visible);
    });

    // Ensure we have focus on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  void _startProgressTimer() {
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _saveCurrentProgress();
    });
  }

  Future<void> _saveCurrentProgress() async {
    if (_controller.videoPlayerController == null) return;
    
    final position = _controller.videoPlayerController!.value.position;
    final duration = _controller.videoPlayerController!.value.duration;
    
    if (duration == Duration.zero) return;

    await _historyService.saveProgress(
      item: widget.item,
      isMovie: widget.isMovie,
      season: widget.season,
      episode: widget.episode,
      episodeName: widget.episodeName,
      position: position,
      duration: duration ?? Duration.zero,
    );
  }

  void _setupController() {
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        expandToFill: true,
        subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
          fontSize: 24, 
          fontColor: Colors.white,
          outlineColor: Colors.black,
        ),
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePlayPause: true,
          enableMute: true,
          enableFullscreen: true,
          enableProgressBar: true,
          enableSkips: false,
          name: widget.title,
          watchingText: widget.isMovie 
              ? '' 
              : '${widget.episodeName} | S${widget.season} E${widget.episode}',
          playerTheme: BetterPlayerTheme.custom,
          customControlsBuilder: (controller, onVisibilityChanged) => TvPlayerControls(
            controller: controller,
            onVisibilityChanged: (visible) {
              onVisibilityChanged(visible);
              if (mounted) setState(() => _controlsVisible = visible);
            },
            onShowSettings: _showSettings,
          ),
        ),
        startAt: widget.startPosition ?? Duration.zero,
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        videoFormat: widget.url.contains('m3u8') || widget.url.contains('playlist') 
            ? BetterPlayerVideoFormat.hls 
            : null,
        useAsmsTracks: true,
        useAsmsAudioTracks: true,
        useAsmsSubtitles: true,
        preferredAudioLanguage: SettingsService().language,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': _getReferer(widget.url),
        },
      ),
    );
  }

  String _getReferer(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return '';
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => PlayerSettingsOverlay(controller: _controller),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveCurrentProgress();
    _visibilitySubscription?.cancel();
    _controller.dispose();
    _mainFocusNode.dispose();
    WakelockPlus.disable(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _mainFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;
        debugPrint('[PlayerScreen] 🔑 key: ${key.debugName}, controlsVisible: $_controlsVisible');

        // Exit keys
        if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        // Action / Directional keys
        if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown || 
            key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
          
          if (!_controlsVisible) {
            debugPrint('[PlayerScreen] 🚀 Showing controls');
            _controller.setControlsVisibility(true);
            return KeyEventResult.handled;
          } else {
            // Already visible, but let's ensure the controller knows
            // This is a safety measure in case states are out of sync
            _controller.setControlsVisibility(true);
          }
          // If controls are visible, let the focus system within the controls handle it
          return KeyEventResult.ignored;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BetterPlayer(controller: _controller),
      ),
    );
  }
}
