import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvPlayerControls extends StatefulWidget {
  final BetterPlayerController controller;
  final Function(bool) onVisibilityChanged;
  final VoidCallback onShowSettings;

  const TvPlayerControls({
    super.key,
    required this.controller,
    required this.onVisibilityChanged,
    required this.onShowSettings,
  });

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  bool _isVisible = false;
  bool _isBuffering = false;
  bool _showBufferingOverlay = false;
  Timer? _bufferingDebounce;
  Timer? _hideTimer;
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _progressBarFocusNode = FocusNode();
  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _rewindFocusNode = FocusNode();
  final FocusNode _ffFocusNode = FocusNode();
  StreamSubscription? _visibilitySubscription;
  int? _lastSeekTimestamp;
  int _seekAccelerationFactor = 1;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    widget.controller.addEventsListener(_onPlayerEvent);
    _visibilitySubscription = widget.controller.controlsVisibilityStream.listen((isVisible) {
      debugPrint('[TvPlayerControls] 📻 Stream received: $isVisible');
      if (isVisible) {
        _showControls();
      } else {
        _hideControls();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _bufferingDebounce?.cancel();
    _playPauseFocusNode.dispose();
    _progressBarFocusNode.dispose();
    _settingsFocusNode.dispose();
    _rewindFocusNode.dispose();
    _ffFocusNode.dispose();
    _visibilitySubscription?.cancel();
    widget.controller.removeEventsListener(_onPlayerEvent);
    super.dispose();
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    debugPrint('[TvPlayerControls] 📩 Received event: ${event.betterPlayerEventType}');
    if (event.betterPlayerEventType == BetterPlayerEventType.controlsVisible) {
      _showControls();
    } else if (event.betterPlayerEventType == BetterPlayerEventType.controlsHiddenEnd) {
      _hideControls();
    } else if (event.betterPlayerEventType == BetterPlayerEventType.bufferingStart) {
      setState(() => _isBuffering = true);
      // Debounce: only show the overlay if buffering lasts >800ms to avoid flash
      _bufferingDebounce?.cancel();
      _bufferingDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _isBuffering) setState(() => _showBufferingOverlay = true);
      });
    } else if (event.betterPlayerEventType == BetterPlayerEventType.bufferingEnd) {
      _bufferingDebounce?.cancel();
      setState(() {
        _isBuffering = false;
        _showBufferingOverlay = false;
      });
    }
  }

  void _showControls() {
    debugPrint('[TvPlayerControls] 👁️ _showControls (isVisible: $_isVisible)');
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
      widget.onVisibilityChanged(true);
      widget.controller.toggleControlsVisibility(true);
      
      _startHideTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playPauseFocusNode.requestFocus();
        debugPrint('[TvPlayerControls] 🎯 Play/Pause focus requested (post-frame). Has focus: ${_playPauseFocusNode.hasFocus}');
      });
    } else {
      _startHideTimer();
    }
  }

  void _hideControls() {
    debugPrint('[TvPlayerControls] 🌑 Setting _isVisible = false');
    if (!_isVisible) return;
    setState(() {
      _isVisible = false;
    });
    widget.onVisibilityChanged(false);
    widget.controller.toggleControlsVisibility(false);
    _hideTimer?.cancel();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isVisible) {
        _hideControls();
      }
    });
  }

  void _togglePlayPause() {
    if (widget.controller.isPlaying() == true) {
      widget.controller.pause();
    } else {
      widget.controller.play();
    }
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Buffering Overlay (debounced, only shows after 800ms of buffering) ───
        if (_showBufferingOverlay)
          _BufferingOverlay(
            controller: widget.controller,
            title: widget.controller.betterPlayerControlsConfiguration.name,
            watchingText: widget.controller.betterPlayerControlsConfiguration.watchingText,
          ),

        // Controls Overlay
        AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_isVisible,
            child: FocusScope(
              canRequestFocus: _isVisible,
              child: Stack(
                children: [
                  // Background Gradient Overlay
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                            stops: const [0.0, 0.2, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Top Bar (Title & Info)
                  Positioned(
                    top: 40,
                    left: 60,
                    right: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.controller.betterPlayerControlsConfiguration.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildInfoBadge('HD'),
                            const SizedBox(width: 12),
                            Text(
                              widget.controller.betterPlayerControlsConfiguration.watchingText ?? '',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
        
                  // Pause Icon (Only when NOT buffering and NOT playing)
                  Center(
                    child: IgnorePointer(
                      child: AnimatedScale(
                        scale: (widget.controller.isPlaying() == true || _isBuffering) ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: const Icon(Icons.pause_rounded, color: Colors.white, size: 60),
                        ),
                      ),
                    ),
                  ),
        
                  // Bottom Bar (Progress & Controls)
                  Positioned(
                    bottom: 40,
                    left: 60,
                    right: 60,
                    child: Builder(
                      builder: (context) {
                        final videoController = widget.controller.videoPlayerController;
                        if (videoController == null) return const SizedBox.shrink();
                        
                        return ValueListenableBuilder(
                          valueListenable: videoController,
                          builder: (context, videoValue, _) {
                            return Column(
                              children: [
                                _buildProgressBar(videoValue),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildTimeText(videoValue.position),
                                    const Spacer(),
                                    _buildRewindButton(),
                                    const SizedBox(width: 24),
                                    _buildPlayPauseButton(),
                                    const SizedBox(width: 24),
                                    _buildFastForwardButton(),
                                    const SizedBox(width: 48),
                                    _buildSettingsButton(),
                                    const Spacer(),
                                    _buildTimeText(videoValue.duration),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      }
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTimeText(Duration? duration) {
    if (duration == null) return const Text("--:--", style: TextStyle(color: Colors.white70, fontSize: 20));
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    String hours = duration.inHours > 0 ? "${twoDigits(duration.inHours)}:" : "";
    return Text(
      "$hours$minutes:$seconds",
      style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildProgressBar([dynamic currentVideoValue]) {
    final videoController = widget.controller.videoPlayerController;
    if (videoController == null) return const SizedBox.shrink();

    if (currentVideoValue != null) {
      final videoValue = currentVideoValue;
      final duration = videoValue.duration as Duration?;
      final position = videoValue.position as Duration;

      final double playedPart = (duration == null || duration == Duration.zero)
          ? 0.0
          : position.inMilliseconds / duration.inMilliseconds;

      final double bufferedPart = (duration == null || duration == Duration.zero)
          ? 0.0
          : _getBufferEnd(videoValue) / duration.inMilliseconds;

      return _buildProgressBarWidget(playedPart, bufferedPart);
    }

    return ValueListenableBuilder(
      valueListenable: videoController,
      builder: (context, videoValue, _) {
        final duration = videoValue.duration;
        final double playedPart = (duration == null || duration == Duration.zero)
            ? 0.0
            : videoValue.position.inMilliseconds / duration.inMilliseconds;

        final double bufferedPart = (duration == null || duration == Duration.zero)
            ? 0.0
            : _getBufferEnd(videoValue) / duration.inMilliseconds;

        return _buildProgressBarWidget(playedPart, bufferedPart);
      },
    );
  }

  double _getBufferEnd(VideoPlayerValue value) {
    if (value.buffered.isEmpty) return 0;
    final pos = value.position.inMilliseconds;
    for (final range in value.buffered) {
      if (range.start.inMilliseconds <= pos && range.end.inMilliseconds >= pos) {
        return range.end.inMilliseconds.toDouble();
      }
    }
    return 0;
  }

  Widget _buildProgressBarWidget(double playedPart, double bufferedPart) {
    final videoController = widget.controller.videoPlayerController;
    if (videoController == null) return const SizedBox.shrink();
    final videoValue = videoController.value;
    return Focus(
      focusNode: _progressBarFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final now = DateTime.now().millisecondsSinceEpoch;
          // Faster acceleration: cap at 20x (10 minutes per jump)
          if (_lastSeekTimestamp != null && (now - _lastSeekTimestamp!) < 400) {
            _seekAccelerationFactor = (_seekAccelerationFactor + 1).clamp(1, 20);
          } else {
            _seekAccelerationFactor = 1;
          }
          _lastSeekTimestamp = now;
          
          final seekAmount = Duration(seconds: 30 * _seekAccelerationFactor);
          widget.controller.seekTo(videoValue.position + seekAmount);
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_lastSeekTimestamp != null && (now - _lastSeekTimestamp!) < 400) {
            _seekAccelerationFactor = (_seekAccelerationFactor + 1).clamp(1, 20);
          } else {
            _seekAccelerationFactor = 1;
          }
          _lastSeekTimestamp = now;

          final seekAmount = Duration(seconds: 30 * _seekAccelerationFactor);
          final target = videoValue.position - seekAmount;
          widget.controller.seekTo(target < Duration.zero ? Duration.zero : target);
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
           _playPauseFocusNode.requestFocus();
           return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
           // Stay on bar or show info (optional)
           return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          void handleSeek(Offset globalPosition) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final Offset localOffset = box.globalToLocal(globalPosition);
            final double relative = localOffset.dx / box.size.width;
            final double percentage = relative.clamp(0.0, 1.0);
            
            final duration = videoController.value.duration;
            if (duration != null) {
              widget.controller.seekTo(duration * percentage);
              _startHideTimer();
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => handleSeek(details.globalPosition),
            onHorizontalDragUpdate: (details) => handleSeek(details.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20), // Larger hit area
              child: Column(
                children: [
                  Container(
                    height: isFocused ? 12 : 6,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Stack(
                      children: [
                        // Buffered progress
                        FractionallySizedBox(
                          widthFactor: (bufferedPart).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        // Played progress
                        FractionallySizedBox(
                          widthFactor: playedPart.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC1D24), // Brand Red
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: isFocused ? [
                                const BoxShadow(color: Color(0xFFEC1D24), blurRadius: 10, spreadRadius: 2)
                              ] : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Focus(
      focusNode: _playPauseFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select) {
          _togglePlayPause();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          // Bottom of screen, just handle to prevent focus loss
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _ffFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _rewindFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: _togglePlayPause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFocused ? Colors.white : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isFocused ? [
                  BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                ] : null,
              ),
              child: Icon(
                widget.controller.isPlaying() == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: isFocused ? Colors.black : Colors.white,
                size: 48,
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildSettingsButton() {
    return Focus(
      focusNode: _settingsFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select) {
          widget.onShowSettings();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _ffFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
           // On rightmost button, just stay
           return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: widget.onShowSettings,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFocused ? Colors.white : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isFocused ? [
                  BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                ] : null,
              ),
              child: Icon(
                Icons.settings_outlined,
                color: isFocused ? Colors.black : Colors.white,
                size: 48,
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildRewindButton() {
    return _buildControlButton(
      focusNode: _rewindFocusNode,
      icon: Icons.replay_10_rounded,
      onPressed: () {
        final pos = widget.controller.videoPlayerController?.value.position ?? Duration.zero;
        widget.controller.seekTo(pos - const Duration(seconds: 10));
        _startHideTimer();
      },
      onLeft: () => KeyEventResult.handled,
      onRight: () => _playPauseFocusNode.requestFocus(),
    );
  }

  Widget _buildFastForwardButton() {
    return _buildControlButton(
      focusNode: _ffFocusNode,
      icon: Icons.forward_10_rounded,
      onPressed: () {
        final pos = widget.controller.videoPlayerController?.value.position ?? Duration.zero;
        widget.controller.seekTo(pos + const Duration(seconds: 10));
        _startHideTimer();
      },
      onLeft: () => _playPauseFocusNode.requestFocus(),
      onRight: () => _settingsFocusNode.requestFocus(),
    );
  }

  Widget _buildControlButton({
    required FocusNode focusNode,
    required IconData icon,
    required VoidCallback onPressed,
    required Function onLeft,
    required Function onRight,
    double size = 48,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final res = onLeft();
          return res is KeyEventResult ? res : KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final res = onRight();
          return res is KeyEventResult ? res : KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFocused ? Colors.white : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isFocused ? [
                  BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                ] : null,
              ),
              child: Icon(
                icon,
                color: isFocused ? Colors.black : Colors.white,
                size: size,
              ),
            ),
          );
        }
      ),
    );
  }
}

// ─── TV Buffering Overlay ─────────────────────────────────────────────────────

class _BufferingOverlay extends StatefulWidget {
  final BetterPlayerController controller;
  final String title;
  final String? watchingText;

  const _BufferingOverlay({
    required this.controller,
    required this.title,
    this.watchingText,
  });

  @override
  State<_BufferingOverlay> createState() => _BufferingOverlayState();
}

class _BufferingOverlayState extends State<_BufferingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Returns seconds buffered ahead of the current position.
  double _bufferedAheadSeconds(VideoPlayerValue value) {
    if (value.buffered.isEmpty || value.duration == null) return 0;
    final pos = value.position.inMilliseconds;
    double maxEnd = 0;
    for (final range in value.buffered) {
      if (range.end.inMilliseconds > pos) {
        maxEnd = range.end.inMilliseconds.toDouble();
      }
    }
    return ((maxEnd - pos) / 1000).clamp(0, value.duration!.inSeconds.toDouble());
  }

  /// Returns buffer fill fraction (0–1) relative to total duration.
  double _bufferFraction(VideoPlayerValue value) {
    if (value.buffered.isEmpty || value.duration == null || value.duration == Duration.zero) return 0;
    final pos = value.position.inMilliseconds;
    double maxEnd = 0;
    for (final range in value.buffered) {
      if (range.end.inMilliseconds > pos) {
        maxEnd = range.end.inMilliseconds.toDouble();
      }
    }
    return ((maxEnd - pos) / value.duration!.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.controller.videoPlayerController;

    return Positioned.fill(
      child: Container(
        // Semi-transparent cinematic backdrop
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Color(0xE6000000),
              Color(0xCC000000),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Pulsing branded spinner
            ScaleTransition(
              scale: _pulseAnim,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      color: const Color(0xFFEC1D24).withOpacity(0.25),
                      strokeWidth: 2,
                      value: 1,
                    ),
                  ),
                  // Spinning progress indicator
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      color: const Color(0xFFEC1D24),
                      strokeWidth: 3,
                      backgroundColor: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  // Center icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.6),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFEC1D24),
                      size: 40,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // "Buffering..." label
            const Text(
              'Buffering…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),

            // Title and episode info
            if (widget.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.watchingText != null && widget.watchingText!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.watchingText!,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 40),

            // Buffer progress bar
            if (videoController != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 120),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: videoController,
                  builder: (context, value, _) {
                    final aheadSecs = _bufferedAheadSeconds(value);
                    final fraction = _bufferFraction(value);

                    return Column(
                      children: [
                        // Bar track
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              // Track
                              Container(
                                height: 4,
                                width: double.infinity,
                                color: Colors.white12,
                              ),
                              // Buffered fill
                              FractionallySizedBox(
                                widthFactor: fraction.clamp(0.0, 1.0),
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFEC1D24), Color(0xFFFF6B6B)],
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x80EC1D24),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Buffered time label
                        if (aheadSecs > 0)
                          Text(
                            '${aheadSecs.toStringAsFixed(0)}s buffered',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
