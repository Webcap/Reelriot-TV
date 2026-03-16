import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late BetterPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  void _setupController() {
    // We'll use a placeholder for context-dependent values initially,
    // though BetterPlayer usually builds its own UI.
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        expandToFill: true,
        subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
          fontSize: 24, // Optimized for distance
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
          // Marvel Red brand color from design.json
          progressBarPlayedColor: const Color(0xFFE60000),
          progressBarHandleColor: Colors.white,
          progressBarBufferedColor: Colors.white30,
          progressBarBackgroundColor: Colors.white10,
          loadingColor: const Color(0xFFE60000),
          controlBarColor: Colors.black45,
          playerTheme: BetterPlayerTheme.material,
        ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        videoFormat: widget.url.contains('m3u8') || widget.url.contains('playlist') 
            ? BetterPlayerVideoFormat.hls 
            : null,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subtitles are already set to a TV-friendly size (24) in initState.
    
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // Wake up controls on any remote interaction
        _controller.setControlsVisibility(true);

        // Exit keys (Escape only, system handles GoBack/Back naturally)
        if (key == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        // Play / Pause
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.mediaPlayPause) {
          if (_controller.isPlaying() == true) {
            _controller.pause();
          } else {
            _controller.play();
          }
          return KeyEventResult.handled;
        }

        // Fast Forward / Rewind (10 seconds)
        if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
          final current = _controller.videoPlayerController?.value.position ?? Duration.zero;
          _controller.seekTo(current + const Duration(seconds: 10));
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
          final current = _controller.videoPlayerController?.value.position ?? Duration.zero;
          _controller.seekTo(current - const Duration(seconds: 10));
          return KeyEventResult.handled;
        }

        // Show Options / Settings on Arrow Up
        if (key == LogicalKeyboardKey.arrowUp) {
          _controller.setControlsVisibility(true);
          // BetterPlayer doesn't have a public 'openSettings' method easy to trigger, 
          // but showing controls allows user to navigate to the settings icon.
          return KeyEventResult.handled;
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
