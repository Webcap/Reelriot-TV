import 'dart:async';
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class TvPlayerControls extends StatefulWidget {
  final CaffeinePlayerController controller;
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
    _visibilitySubscription = widget.controller.controlsVisibilityStream.listen(
      (isVisible) {
        if (isVisible) {
          _showControls();
        } else {
          _hideControls();
        }
      },
    );
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

  void _onPlayerEvent(CaffeinePlayerEvent event) {
    if (event.type == CaffeinePlayerEventType.controlsVisible) {
      _showControls();
    } else if (event.type == CaffeinePlayerEventType.controlsHiddenEnd) {
      _hideControls();
    } else if (event.type == CaffeinePlayerEventType.bufferingStart) {
      setState(() => _isBuffering = true);
      _bufferingDebounce?.cancel();
      _bufferingDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _isBuffering) {
          setState(() => _showBufferingOverlay = true);
        }
      });
    } else if (event.type == CaffeinePlayerEventType.bufferingEnd) {
      _bufferingDebounce?.cancel();
      setState(() {
        _isBuffering = false;
        _showBufferingOverlay = false;
      });
    }
  }

  void _showControls() {
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
      widget.onVisibilityChanged(true);
      widget.controller.toggleControlsVisibility(true);

      _startHideTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playPauseFocusNode.requestFocus();
      });
    } else {
      _startHideTimer();
    }
  }

  void _hideControls() {
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
        if (_showBufferingOverlay)
          _BufferingOverlay(
            controller: widget.controller,
            title: widget.controller.name,
            watchingText: widget.controller.watchingText,
          ),

        Visibility(
          visible: _isVisible,
          maintainState: true,
          maintainAnimation: true,
          child: AnimatedOpacity(
            opacity: _isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_isVisible,
              child: FocusScope(
                canRequestFocus: _isVisible,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7),
                              ],
                              stops: const [0.0, 0.2, 0.8, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      top: 40,
                      left: 60,
                      right: 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.controller.name.toUpperCase(),
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
                                widget.controller.watchingText ?? '',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    Center(
                      child: IgnorePointer(
                        child: AnimatedScale(
                          scale:
                              (widget.controller.isPlaying() == true ||
                                  _isBuffering)
                              ? 0.0
                              : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white24,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.pause_rounded,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 40,
                      left: 60,
                      right: 60,
                      child: ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final playerState = widget.controller.player.state;

                          return Column(
                            children: [
                              _buildProgressBar(playerState),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildTimeText(playerState.position),
                                  const Spacer(),
                                  _buildRewindButton(),
                                  const SizedBox(width: 24),
                                  _buildPlayPauseButton(),
                                  const SizedBox(width: 24),
                                  _buildFastForwardButton(),
                                  const SizedBox(width: 48),
                                  _buildSettingsButton(),
                                  const Spacer(),
                                  _buildTimeText(playerState.duration),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTimeText(Duration? duration) {
    if (duration == null) {
      return const Text(
        "--:--",
        style: TextStyle(color: Colors.white70, fontSize: 20),
      );
    }
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    String hours = duration.inHours > 0
        ? "${twoDigits(duration.inHours)}:"
        : "";
    return Text(
      "$hours$minutes:$seconds",
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildProgressBar([PlayerState? currentState]) {
    final state = currentState ?? widget.controller.player.state;
    final duration = state.duration;
    final position = state.position;
    final buffer = state.buffer;

    final double playedPart = (duration == Duration.zero)
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;

    final double bufferedPart = (duration == Duration.zero)
        ? 0.0
        : (position.inMilliseconds + buffer.inMilliseconds) /
              duration.inMilliseconds;

    return _buildProgressBarWidget(playedPart, bufferedPart, state);
  }

  Widget _buildProgressBarWidget(
    double playedPart,
    double bufferedPart,
    PlayerState state,
  ) {
    return Focus(
      focusNode: _progressBarFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (TvKeys.isRight(event.logicalKey)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_lastSeekTimestamp != null && (now - _lastSeekTimestamp!) < 400) {
            _seekAccelerationFactor = (_seekAccelerationFactor + 1).clamp(
              1,
              20,
            );
          } else {
            _seekAccelerationFactor = 1;
          }
          _lastSeekTimestamp = now;

          final seekAmount = Duration(seconds: 30 * _seekAccelerationFactor);
          widget.controller.seekTo(state.position + seekAmount);
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (TvKeys.isLeft(event.logicalKey)) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (_lastSeekTimestamp != null && (now - _lastSeekTimestamp!) < 400) {
            _seekAccelerationFactor = (_seekAccelerationFactor + 1).clamp(
              1,
              20,
            );
          } else {
            _seekAccelerationFactor = 1;
          }
          _lastSeekTimestamp = now;

          final seekAmount = Duration(seconds: 30 * _seekAccelerationFactor);
          final target = state.position - seekAmount;
          widget.controller.seekTo(
            target < Duration.zero ? Duration.zero : target,
          );
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (TvKeys.isDown(event.logicalKey)) {
          _playPauseFocusNode.requestFocus();
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

            final duration = widget.controller.player.state.duration;
            if (duration != Duration.zero) {
              widget.controller.seekTo(duration * percentage);
              _startHideTimer();
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => handleSeek(details.globalPosition),
            onHorizontalDragUpdate: (details) =>
                handleSeek(details.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Container(
                height: isFocused ? 12 : 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Stack(
                  children: [
                    FractionallySizedBox(
                      widthFactor: (bufferedPart).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: playedPart.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC1D24),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isFocused
                              ? [
                                  const BoxShadow(
                                    color: Color(0xFFEC1D24),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Focus(
      focusNode: _playPauseFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (TvKeys.isSelect(event.logicalKey)) {
          _togglePlayPause();
          return KeyEventResult.handled;
        }
        if (TvKeys.isUp(event.logicalKey)) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (TvKeys.isRight(event.logicalKey)) {
          _ffFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (TvKeys.isLeft(event.logicalKey)) {
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
              ),
              child: Icon(
                widget.controller.isPlaying() == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: isFocused ? Colors.black : Colors.white,
                size: 48,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsButton() {
    return Focus(
      focusNode: _settingsFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (TvKeys.isSelect(event.logicalKey)) {
          widget.onShowSettings();
          return KeyEventResult.handled;
        }
        if (TvKeys.isUp(event.logicalKey)) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (TvKeys.isLeft(event.logicalKey)) {
          _ffFocusNode.requestFocus();
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
              ),
              child: Icon(
                Icons.settings_outlined,
                color: isFocused ? Colors.black : Colors.white,
                size: 48,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRewindButton() {
    return _buildControlButton(
      focusNode: _rewindFocusNode,
      icon: Icons.replay_10_rounded,
      onPressed: () {
        final pos = widget.controller.player.state.position;
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
        final pos = widget.controller.player.state.position;
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
        if (TvKeys.isSelect(event.logicalKey)) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (TvKeys.isUp(event.logicalKey)) {
          _progressBarFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (TvKeys.isLeft(event.logicalKey)) {
          final res = onLeft();
          return res is KeyEventResult ? res : KeyEventResult.handled;
        }
        if (TvKeys.isRight(event.logicalKey)) {
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
              ),
              child: Icon(
                icon,
                color: isFocused ? Colors.black : Colors.white,
                size: size,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BufferingOverlay extends StatefulWidget {
  final CaffeinePlayerController controller;
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

  double _bufferFraction(PlayerState state) {
    if (state.duration == Duration.zero) return 0;
    return (state.buffer.inMilliseconds / state.duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.player.state;

        return Positioned.fill(
          child: Container(
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
            child: RepaintBoundary(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            color: const Color(
                              0xFFEC1D24,
                            ).withValues(alpha: 0.25),
                            strokeWidth: 2,
                            value: 1,
                          ),
                        ),
                        const SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            color: Color(0xFFEC1D24),
                            strokeWidth: 3,
                          ),
                        ),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.6),
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
                  const Text(
                    'Buffering…',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (widget.title.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 120),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              Container(
                                height: 4,
                                width: double.infinity,
                                color: Colors.white12,
                              ),
                              FractionallySizedBox(
                                widthFactor: _bufferFraction(
                                  state,
                                ).clamp(0.0, 1.0),
                                child: Container(
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFEC1D24),
                                        Color(0xFFFF6B6B),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (state.buffer > Duration.zero)
                          Text(
                            '${(state.buffer.inMilliseconds / 1000).toStringAsFixed(0)}s buffered',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
