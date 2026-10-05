import 'dart:async';
import 'dart:convert';

import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart'
    show CaffeinePlayerSubtitlesSource;
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/utils/wakelock_manager.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Last-resort player for providers whose video renders inside an
/// origin-keyed iframe we can't reach from injected JS to extract a direct
/// stream URL (e.g. vixsrc). Shows the provider's page itself and lets the
/// WebView's own browser engine decode/render the video in place, since that
/// engine can play it even though our script can't see inside it.
///
/// Remote/D-pad interaction with the page's own on-screen controls is not
/// reliable (no touch input), so only Back is wired up explicitly.
class EmbeddedWebPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final dynamic item;
  final bool isMovie;
  final int? season;
  final int? episode;
  final int? episodeId;
  final String? episodeName;
  final Duration? startPosition;
  final List<CaffeinePlayerSubtitlesSource>? subtitles;

  const EmbeddedWebPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.item,
    required this.isMovie,
    this.season,
    this.episode,
    this.episodeId,
    this.episodeName,
    this.startPosition,
    this.subtitles,
  });

  @override
  State<EmbeddedWebPlayerScreen> createState() =>
      _EmbeddedWebPlayerScreenState();
}

class _EmbeddedWebPlayerScreenState extends State<EmbeddedWebPlayerScreen> {
  static const _focusChannel = MethodChannel('reelriot.tv/webview_focus');

  late final WebViewController _controller;
  final FocusNode _focusNode = FocusNode();
  final WatchHistoryService _historyService = WatchHistoryService();
  Timer? _saveTimer;
  bool _loading = true;
  bool _showLimitedControlsNotice = false;
  Timer? _limitedControlsNoticeTimer;

  // Real progress, when the page's own player cooperates by posting
  // {currentTime, duration} via window.postMessage (see _attachProgressJs)
  // — the actual <video> element lives inside an origin-keyed iframe our
  // injected script can't reach directly, so this is the only channel a
  // provider can report real position through, and not all of them do.
  int _currentPositionMs = 0;
  int _durationMs = 0;
  bool _hasRealProgressSignal = false;
  bool _hasFinished = false;

  // Fallback for providers that never post real progress: instead of
  // counting flat wall-clock time since the page loaded (which would count
  // buffering/ad delay as "watched" and never notice a pause), we poll
  // Android's AudioManager for whether audio is actively playing right now
  // and only accumulate elapsed time during segments where it is. Audio
  // starting/stopping is a solid proxy for the video actually playing,
  // and it's a native OS-level signal — it doesn't depend on the provider's
  // page cooperating with anything, unlike postMessage.
  Timer? _audioPollTimer;
  int _accumulatedPlayMs = 0;
  DateTime? _currentPlaySegmentStart;

  int get _estimatedPositionMs {
    final startMs = widget.startPosition?.inMilliseconds ?? 0;
    var playedMs = _accumulatedPlayMs;
    if (_currentPlaySegmentStart != null) {
      playedMs += DateTime.now().difference(_currentPlaySegmentStart!).inMilliseconds;
    }
    return (startMs + playedMs).clamp(0, _durationMs);
  }

  Future<void> _pollAudioActive() async {
    bool active;
    try {
      active = await _focusChannel.invokeMethod<bool>('isAudioActive') ?? false;
    } catch (_) {
      active = false;
    }

    final wasActive = _currentPlaySegmentStart != null;
    if (active && !wasActive) {
      _currentPlaySegmentStart = DateTime.now();
    } else if (!active && wasActive) {
      _accumulatedPlayMs +=
          DateTime.now().difference(_currentPlaySegmentStart!).inMilliseconds;
      _currentPlaySegmentStart = null;
    }
  }

  int _estimateDurationMs() {
    if (widget.isMovie) {
      final item = widget.item;
      if (item is core.MovieDetail && (item.runtime ?? 0) > 0) {
        return item.runtime! * 60 * 1000;
      }
      return const Duration(minutes: 100).inMilliseconds;
    }
    return const Duration(minutes: 45).inMilliseconds;
  }

  void _runJs(String js) {
    if (!mounted) return;
    _controller.runJavaScript(js);
  }

  // Shows the "limited controls" disclosure for a few seconds after the
  // page loads, then fades it out — long enough to read once, not a
  // permanent fixture sitting over the video for the whole session.
  void _showLimitedControlsNoticeBriefly() {
    _limitedControlsNoticeTimer?.cancel();
    if (mounted) setState(() => _showLimitedControlsNotice = true);
    _limitedControlsNoticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showLimitedControlsNotice = false);
    });
  }

  // Hands the TV remote's D-pad/media keys to the WebView's native Android
  // view so the browser engine can route them into the page's own player
  // (including into nested iframes, since that's native input dispatch, not
  // script access). Retried a couple of times since the platform view isn't
  // guaranteed to be attached the instant the page finishes loading.
  void _requestNativeFocus() {
    _focusChannel
        .invokeMethod('requestFocus')
        .then((found) => debugPrint('[EmbeddedWebPlayer] requestFocus -> found=$found'))
        .catchError((e) => debugPrint('[EmbeddedWebPlayer] requestFocus error: $e'));
  }

  // Best-effort data for the injected JS: a one-time resume seek and
  // subtitle <track> injection for whatever <video> elements our script can
  // actually reach (same-origin ones — the cross-origin case this screen
  // primarily exists for can't be helped here; that's fixed upstream by
  // resolving a direct stream before ever falling back to this screen).
  // Passed as base64 JSON to sidestep any JS string-escaping concerns with
  // provider-supplied subtitle labels/URLs.
  String _buildProgressJs() {
    final startSeconds =
        (widget.startPosition?.inMilliseconds ?? 0) / 1000.0;
    final subsPayload = (widget.subtitles ?? [])
        .where((s) => s.url != null && s.url!.isNotEmpty)
        .map((s) => {
              'url': s.url,
              'label': s.name ?? 'Subtitle',
              'isDefault': s.isDefault,
            })
        .toList();
    final payloadJson = jsonEncode({
      'startSeconds': startSeconds,
      'subtitles': subsPayload,
    });
    final encodedPayload = base64Encode(utf8.encode(payloadJson));
    return _attachProgressJsTemplate.replaceFirst(
      '__PAYLOAD_B64__',
      encodedPayload,
    );
  }

  Future<void> _saveProgress({bool isFinished = false}) async {
    if (_durationMs <= 0) return;

    var positionMs = _hasRealProgressSignal ? _currentPositionMs : _estimatedPositionMs;
    if (isFinished) positionMs = _durationMs;

    // Don't clobber a real saved resume position with a near-zero reading
    // taken before playback has meaningfully started.
    final startMs = widget.startPosition?.inMilliseconds ?? 0;
    if (!isFinished && positionMs <= 5000 && startMs > 5000) {
      return;
    }

    await _historyService.saveProgress(
      item: widget.item,
      isMovie: widget.isMovie,
      season: widget.season,
      episode: widget.episode,
      episodeId: widget.episodeId,
      episodeName: widget.episodeName,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: _durationMs),
    );
  }

  Future<void> _exit() async {
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  // Mirrors PlayerScreen's handling of CaffeinePlayerEventType.finished:
  // save the final position as complete and close, instead of sitting on a
  // finished video waiting for the next 30s tick or a manual Back press.
  Future<void> _handleFinished() async {
    if (_hasFinished) return;
    _hasFinished = true;
    await _saveProgress(isFinished: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    WakelockManager.enable();
    _currentPositionMs = widget.startPosition?.inMilliseconds ?? 0;
    _durationMs = _estimateDurationMs();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PlaybackProgress',
        onMessageReceived: (message) {
          debugPrint('[EmbeddedWebPlayer] progress message: ${message.message}');
          try {
            final data = jsonDecode(message.message);
            if (data is Map) {
              final cur = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
              final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
              final ended = data['ended'] == true;
              if (cur > 0) {
                _hasRealProgressSignal = true;
                _currentPositionMs = (cur * 1000).toInt();
                if (dur > 0) _durationMs = (dur * 1000).toInt();
              }
              // Either the page told us explicitly, or we're close enough
              // to the end (matches the ratio saveProgress() itself uses to
              // decide "completed" server-side) that waiting for another
              // signal isn't worth it.
              final nearEnd = dur > 0 && cur > 0 && (cur / dur) >= 0.95;
              if (ended || nearEnd) _handleFinished();
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _runJs(_adBlockJs),
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _showLimitedControlsNoticeBriefly();
            _audioPollTimer ??= Timer.periodic(
              const Duration(seconds: 1),
              (_) => _pollAudioActive(),
            );
            _runJs(_adBlockJs);
            _runJs(_buildProgressJs());
            for (final ms in [500, 1200, 2500, 5000]) {
              Future<void>.delayed(Duration(milliseconds: ms), () {
                _runJs(_adBlockJs);
                _runJs(_buildProgressJs());
              });
            }
            for (final ms in [300, 1000, 2500]) {
              Future<void>.delayed(
                Duration(milliseconds: ms),
                _requestNativeFocus,
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_hasRealProgressSignal && _estimatedPositionMs >= _durationMs) {
        _handleFinished();
      } else if (_hasRealProgressSignal) {
        // Only autosave mid-session when we have a real signal (postMessage
        // or a reachable <video> element). The audio-active heuristic alone
        // is too noisy to trust for a periodic write — it would repeatedly
        // overwrite a good resume point with a guess. We still save the
        // best-available estimate once, on exit/finish, below.
        _saveProgress();
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _limitedControlsNoticeTimer?.cancel();
    _audioPollTimer?.cancel();
    _focusChannel.invokeMethod('releaseFocus').catchError((_) {});
    WakelockManager.disable();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (TvKeys.isBack(event.logicalKey)) {
          _exit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _exit();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              // Honest disclosure: this fallback can't offer a real seek bar
              // or subtitle toggle (the provider's own on-page controls
              // aren't reliably reachable via D-pad), so say so instead of
              // silently doing nothing when the user tries. Shown briefly
              // after load, then faded out rather than left sitting over
              // the video for the whole session.
              if (!_loading)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showLimitedControlsNotice ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            'Limited controls on this source — press Back to exit',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const String _adBlockJs = r'''
  (function() {
    try {
      Object.defineProperty(window, 'open', {
        value: function() { return null; },
        writable: false,
        configurable: false
      });
    } catch(e) {}
    try {
      window.alert = function() {};
      window.confirm = function() { return false; };
      window.prompt = function() { return null; };
    } catch(e) {}
  })();
''';

/// Reports playback progress back to the app, and does what it can for
/// resume/subtitles on whatever <video> elements it can actually reach.
///
/// The actual <video> element is normally inside an origin-keyed iframe our
/// script can't reach directly (contentDocument/contentWindow access
/// throws), so progress primarily relies on the provider's own player
/// posting {currentTime, duration} to its parent via window.postMessage — a
/// channel explicitly designed to cross that isolation boundary, unlike
/// direct DOM/JS access. If a provider's player doesn't do this, progress
/// falls back to a cruder on-device heuristic (see `_pollAudioActive`).
///
/// For providers whose <video> IS same-origin reachable (not every provider
/// that lands on this screen is cross-origin — some land here for other
/// extraction failures), this also does a one-time seek to resume where the
/// user left off, and injects <track> elements for our already-resolved
/// subtitle list, since there's no custom control surface here to toggle
/// them — see the on-screen "limited controls" notice.
///
/// `__PAYLOAD_B64__` is replaced by `_buildProgressJs()` with a base64 JSON
/// blob of `{startSeconds, subtitles: [{url, label, isDefault}]}`, avoiding
/// any JS-string-escaping concerns with provider/subtitle text.
const String _attachProgressJsTemplate = r'''
  (function() {
    var __rrPayload = JSON.parse(atob('__PAYLOAD_B64__'));

    function sendProgress(cur, dur, ended) {
      try {
        if (typeof PlaybackProgress !== 'undefined' && cur > 0) {
          PlaybackProgress.postMessage(JSON.stringify({
            currentTime: cur,
            duration: dur || 0,
            ended: !!ended
          }));
        }
      } catch(e) {}
    }

    function applyResumeAndSubtitles(v) {
      if (!v.__rr_seeked && __rrPayload.startSeconds > 1) {
        v.__rr_seeked = true;
        try {
          if (v.readyState > 0) {
            v.currentTime = __rrPayload.startSeconds;
          } else {
            v.addEventListener('loadedmetadata', function() {
              try { v.currentTime = __rrPayload.startSeconds; } catch(e) {}
            }, { once: true });
          }
        } catch(e) {}
      }

      if (!v.__rr_subs_injected && __rrPayload.subtitles && __rrPayload.subtitles.length) {
        v.__rr_subs_injected = true;
        try {
          __rrPayload.subtitles.forEach(function(s) {
            var track = document.createElement('track');
            track.kind = 'subtitles';
            track.label = s.label;
            track.src = s.url;
            track.default = !!s.isDefault;
            v.appendChild(track);
          });
        } catch(e) {}
      }
    }

    function hookVideos() {
      try {
        document.querySelectorAll('video').forEach(function(v) {
          if (!v.__rr_tracked) {
            v.__rr_tracked = true;
            ['timeupdate', 'seeked', 'pause', 'play'].forEach(function(ev) {
              v.addEventListener(ev, function() {
                sendProgress(v.currentTime, v.duration || 0, false);
              });
            });
            v.addEventListener('ended', function() {
              sendProgress(v.duration || v.currentTime, v.duration || 0, true);
            });
          }
          applyResumeAndSubtitles(v);
          if (v.currentTime > 0) sendProgress(v.currentTime, v.duration || 0, false);
        });
      } catch(e) {}
    }

    hookVideos();
    if (!window.__rr_progress_interval) {
      window.__rr_progress_interval = setInterval(hookVideos, 1000);
    }

    if (!window.__rr_msg_tracked) {
      window.__rr_msg_tracked = true;
      window.addEventListener('message', function(e) {
        try {
          var d = e.data;
          if (typeof d === 'string') {
            try { d = JSON.parse(d); } catch(_) { return; }
          }
          if (!d || typeof d !== 'object') return;
          var cur = d.currentTime || d.current_time || d.position || d.time;
          var dur = d.duration || d.totalTime || d.total_time || 0;
          var ended = d.ended === true || d.event === 'ended' || d.type === 'ended';
          if ((cur && cur > 0) || ended) sendProgress(cur || dur, dur, ended);
        } catch(ex) {}
      });
    }
  })();
''';
