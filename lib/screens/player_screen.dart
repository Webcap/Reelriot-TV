import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/utils/tv_keys.dart';
import 'package:caffeine_tv/widgets/player_settings_overlay.dart';
import 'package:caffeine_tv/widgets/tv_player_controls.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/scheduler.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
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
    this.referrer,
    this.providerCode,
    this.allProviders,
    this.headers,
  });

  final String url;
  final String title;
  final dynamic item;
  final bool isMovie;
  final int? season;
  final int? episode;
  final int? episodeId;
  final String? episodeName;
  final Duration? startPosition;
  final String? referrer;
  final String? providerCode;
  final List<Map<String, String>>? allProviders;
  final Map<String, String>? headers;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  final WatchHistoryService _historyService = WatchHistoryService();
  final FocusNode _mainFocusNode = FocusNode();
  Timer? _saveTimer;
  bool _controlsVisible = false;
  StreamSubscription? _visibilitySubscription;
  int _retryCount = 0;
  final ApiService _api = ApiService();
  bool _isRefreshing = false;
  bool _isDisposed = false;
  bool _isHandlingException = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    
    // Check if we are in a phase where setState is allowed
    // During build/layout/paint, we must delay to the next frame
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || 
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          setState(fn);
        }
      });
    } else {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); 
    _setupController();
    _startProgressTimer();
    
    _visibilitySubscription = _controller?.controlsVisibilityStream.listen((visible) {
      _safeSetState(() => _controlsVisible = visible);
    });

    // Ensure we have focus on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  void _startProgressTimer() {
    _saveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveCurrentProgress();
    });
  }

  Future<void> _saveCurrentProgress({bool isFinished = false}) async {
    if (_controller == null || _controller!.videoPlayerController == null) return;
    
    final duration = _controller!.videoPlayerController!.value.duration ?? Duration.zero;
    if (duration == Duration.zero) return;

    final position = isFinished 
        ? duration 
        : _controller!.videoPlayerController!.value.position;
    
    await _historyService.saveProgress(
      item: widget.item,
      isMovie: widget.isMovie,
      season: widget.season,
      episode: widget.episode,
      episodeId: widget.episodeId,
      episodeName: widget.episodeName,
      position: position,
      duration: duration,
    );
  }

  void _setupController() {
    if (widget.url.isEmpty) {
      _safeSetState(() {
        _hasError = true;
        _errorMessage = 'Invalid video URL';
      });
      return;
    }

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
              _safeSetState(() => _controlsVisible = visible);
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
        preferredAudioLanguage: SettingsService().defaultAudioLanguage,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': widget.referrer ?? _getReferer(widget.url),
          'Referrer': widget.referrer ?? _getReferer(widget.url),
          'Origin': _getOrigin(widget.referrer ?? _getReferer(widget.url)),
          'Accept': '*/*',
          'Connection': 'keep-alive',
          ...?widget.headers,
        },
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 60000,
          maxBufferMs: 120000,
          bufferForPlaybackMs: 5000,
          bufferForPlaybackAfterRebufferMs: 10000,
        ),
      ),
    );
    debugPrint('[PlayerScreen] 📺 Playing: ${widget.url}');
    debugPrint('[PlayerScreen] 🔗 Referrer: ${widget.referrer ?? _getReferer(widget.url)}');
 
    _controller!.addEventsListener((event) async {
      if (_isDisposed) return;
      if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
        debugPrint('[PlayerScreen] 🎉 Video finished, saving final progress (100%) and closing');
        await _saveCurrentProgress(isFinished: true);
        if (mounted && !_isDisposed) Navigator.of(context).pop();
      } else if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        // Try multiple times as tracks might load late in HLS manifest
        _selectPreferredAudioTrack();
        Future.delayed(const Duration(milliseconds: 500), () => _selectPreferredAudioTrack());
        Future.delayed(const Duration(milliseconds: 1500), () => _selectPreferredAudioTrack());
        Future.delayed(const Duration(milliseconds: 3000), () => _selectPreferredAudioTrack());
        Future.delayed(const Duration(milliseconds: 5000), () => _selectPreferredAudioTrack());
      } else if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
        if (!_isDisposed) _handlePlayerException(event);
      }
    });
  }

  bool get _isSports => !widget.isMovie && (widget.season == null || widget.episode == null);

  void _handlePlayerException(BetterPlayerEvent event) async {
    if (_isHandlingException || _isRefreshing || _isDisposed) return;
    _isHandlingException = true;
    
    final exception = event.parameters?['exception'];
    debugPrint('[PlayerScreen] ⚠️ Playback exception: $exception');
    
    // Only retry for network/source errors, especially if we've been playing for a while
    // or if the error code suggests a source issue (2001, 2002)
    final errorStr = exception?.toString().toLowerCase() ?? '';
    final isSourceError = errorStr.contains('source error') || 
                         errorStr.contains('httpdatasource') ||
                         errorStr.contains('sockettimeout') ||
                         errorStr.contains('unexpected end of stream');

    if (isSourceError && _retryCount < 3) {
      _retryCount++;
      debugPrint('[PlayerScreen] 🔄 Attempting to re-fetch stream URL (Retry $_retryCount/3)...');
      
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _isRefreshing = true;
          _hasError = false; 
        });
      }

      try {
        final currentPosition = _controller?.videoPlayerController?.value.position ?? widget.startPosition ?? Duration.zero;
        
        String? newUrl;
        String? newReferrer;
        Map<String, String>? newHeaders;

        if (_isSports) {
            // Special refresh logic for sports: re-query Supabase
            final refreshResult = await _refreshSportsStream();
            if (refreshResult != null) {
                newUrl = refreshResult['url'];
                newReferrer = refreshResult['referrer'];
            }
        } else {
            // Robust ID access for both MovieDetail/TvShowDetail objects and Map objects
            final dynamic rawId = widget.item is Map 
                ? (widget.item['media_id'] ?? widget.item['id'])
                : widget.item?.id;
            
            final int? mediaId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

            if (mediaId == null) {
                debugPrint('[PlayerScreen] ❌ Cannot retry: mediaId is null or invalid ($rawId)');
                _isHandlingException = false;
                _safeSetState(() => _isRefreshing = false);
                return;
            }

            final core.ProviderStreamResponse response;
            if (widget.isMovie) {
                response = await _api.fetchMovieStream(mediaId, provider: widget.providerCode ?? 'vidlink');
            } else {
                response = await _api.fetchTvStream(
                    mediaId, 
                    widget.season!, 
                    widget.episode!, 
                    provider: widget.providerCode ?? 'vidlink'
                );
            }

            if (response.success && response.links != null && response.links!.isNotEmpty) {
                newUrl = response.links!.first.url;
                newHeaders = response.links!.first.headers;
            }
        }

        if (newUrl != null && newUrl.isNotEmpty) {
          debugPrint('[PlayerScreen] ✅ Re-fetched new URL: $newUrl');
          
          if (!mounted) return;

          // Re-initialize the player with the new URL and the current position
          _controller?.setupDataSource(
            BetterPlayerDataSource(
              BetterPlayerDataSourceType.network,
              newUrl,
              videoFormat: newUrl.contains('m3u8') || newUrl.contains('playlist') 
                  ? BetterPlayerVideoFormat.hls 
                  : null,
              useAsmsTracks: true,
              useAsmsAudioTracks: true,
              useAsmsSubtitles: true,
              preferredAudioLanguage: SettingsService().defaultAudioLanguage,
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': newReferrer ?? widget.referrer ?? _getReferer(newUrl),
                ...?newHeaders,
              },
              bufferingConfiguration: const BetterPlayerBufferingConfiguration(
                minBufferMs: 60000,
                maxBufferMs: 120000,
                bufferForPlaybackMs: 5000,
                bufferForPlaybackAfterRebufferMs: 10000,
              ),
            ),
          ).then((_) {
            if (_isDisposed) return;
            _controller?.play();
            _controller?.seekTo(currentPosition);
          });

          // Seek to the last known position after initialization
          late Function(BetterPlayerEvent) refreshListener;
          refreshListener = (refreshEvent) {
            if (refreshEvent.betterPlayerEventType == BetterPlayerEventType.initialized) {
              _controller?.seekTo(currentPosition);
              _controller?.play();
              _controller?.removeEventsListener(refreshListener);
            }
          };
          _controller?.addEventsListener(refreshListener);
        } else {
          debugPrint('[PlayerScreen] ❌ Re-fetch failed or returned no links');
          _isHandlingException = false;
          _safeSetState(() {
            _isRefreshing = false;
            if (widget.isMovie || widget.episode != null) {
              // For movies/tv, show settings (which includes source selector) if reach max retries or immediate fail
              _showSettings();
            } else {
              _hasError = true;
              _errorMessage = 'Failed to refresh stream. Please try again later.';
            }
          });
        }
      } catch (e) {
        debugPrint('[PlayerScreen] ❌ Error during refresh: $e');
        _isHandlingException = false;
        _safeSetState(() => _isRefreshing = false);
      }
    } else {
      debugPrint('[PlayerScreen] ❌ Max retries reached or non-source error');
      _isHandlingException = false;
      _safeSetState(() {
        _isRefreshing = false;
        _hasError = true;
        _errorMessage = exception?.toString() ?? 'Playback error';
      });
    }
  }

  Future<Map<String, String?>?> _refreshSportsStream() async {
    try {
        final String? eventId = widget.item is Map ? widget.item['id']?.toString() : null;
        if (eventId == null) return null;

        debugPrint('[PlayerScreen] 🔄 Querying Supabase for fresh sports stream (ID: $eventId)...');
        final response = await Supabase.instance.client
            .from('live_streams')
            .select('video_url, referrer, sources')
            .eq('id', eventId)
            .maybeSingle();
        
        if (response != null && response['video_url'] != null && response['video_url'].isNotEmpty) {
            return {
                'url': response['video_url'] as String,
                'referrer': response['referrer'] as String?,
                'sources': response['sources'],
            };
        }
    } catch (e) {
        debugPrint('[PlayerScreen] ❌ Supabase sports refresh error: $e');
    }
    return null;
  }

  void _selectPreferredAudioTrack() {
    if (_controller == null || _isDisposed) return;
    
    final tracks = _controller!.betterPlayerAsmsAudioTracks;
    if (tracks == null || tracks.isEmpty) {
      debugPrint('[PlayerScreen] 🎧 No audio tracks available yet.');
      return;
    }

    final preferred = SettingsService().defaultAudioLanguage.toLowerCase();
    debugPrint('[PlayerScreen] 🎧 Attempting to select audio track: $preferred');
    
    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      final label = track.label?.toLowerCase() ?? '';
      debugPrint('[PlayerScreen]   - Track: lang="$lang", label="$label"');
      
      final isMatch = lang == preferred || 
                     lang.startsWith(preferred) || 
                     label.startsWith(preferred) ||
                     label.contains(preferred) ||
                     (preferred == 'en' && label.contains('english'));

      if (isMatch) {
        debugPrint('[PlayerScreen] ✅ Match found! Selecting track: $label ($lang)');
        _controller!.setAudioTrack(track);
        return;
      }
    }
  }

  String _getReferer(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return '';
    }
  }
  
  String _getOrigin(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.isEmpty || uri.host.isEmpty) return url.replaceAll(RegExp(r'/$'), '');
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url.replaceAll(RegExp(r'/$'), '');
    }
  }

  void _showSettings() {
    if (_controller == null) return;
    showDialog(
      context: context,
      builder: (context) => PlayerSettingsOverlay(
        controller: _controller!,
        currentProvider: widget.providerCode,
        allProviders: widget.allProviders,
        onChangeProvider: (newProviderCode) {
          // Close settings dialog
          Navigator.of(context).pop();
          final currentPos = _controller?.videoPlayerController?.value.position;
          debugPrint('[PlayerScreen] 🔄 Changing provider to: $newProviderCode');
          
          if (_isSports && widget.allProviders != null) {
            // Check if newProviderCode is one of our mirror URLs
            final source = widget.allProviders!.firstWhere(
              (p) => p['code'] == newProviderCode,
              orElse: () => {},
            );
            
            if (source.isNotEmpty) {
              debugPrint('[PlayerScreen] ⚾ Sports mirror switch to: $newProviderCode');
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                    url: newProviderCode,
                    title: widget.title,
                    item: widget.item,
                    isMovie: false,
                    referrer: source['referrer'],
                    allProviders: widget.allProviders,
                    startPosition: currentPos,
                  ),
                ),
              );
              return;
            }
          }

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => _buildVideoLoader(newProviderCode, currentPos),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoLoader(String providerCode, Duration? position) {
    return VideoLoaderScreen(
      movie: widget.isMovie ? widget.item : null,
      tvShow: !widget.isMovie ? widget.item : null,
      season: widget.season,
      episode: widget.episode,
      episodeId: widget.episodeId,
      episodeName: widget.episodeName,
      startPosition: position,
      preferredProvider: providerCode,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _saveTimer?.cancel();
    _saveCurrentProgress(); // Best effort save
    _visibilitySubscription?.cancel();
    
    // Safety check before controller methods
    try {
      _controller?.pause();
      _controller?.dispose();
    } catch (e) {
      debugPrint('[PlayerScreen] Error during controller disposal: $e');
    }
    
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

        // Back / Exit
        if (TvKeys.isBack(key)) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        // Dedicated media remote buttons (work whether controls are visible or not)
        if (TvKeys.isPlayPause(key)) {
          debugPrint('[PlayerScreen] ⏯️ Media Play/Pause key');
          if (_controller?.isPlaying() == true) {
            _controller?.pause();
          } else {
            _controller?.play();
          }
          if (!_controlsVisible && !_isDisposed) _controller?.setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaFastForward(key)) {
          debugPrint('[PlayerScreen] ⏩ Media Fast Forward key');
          final pos = _controller?.videoPlayerController?.value.position;
          if (pos != null) {
            _controller?.seekTo(pos + const Duration(seconds: 10));
          }
          if (!_controlsVisible && !_isDisposed) _controller?.setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaRewind(key)) {
          debugPrint('[PlayerScreen] ⏪ Media Rewind key');
          final pos = _controller?.videoPlayerController?.value.position;
          if (pos != null) {
            final target = pos - const Duration(seconds: 10);
            _controller?.seekTo(target < Duration.zero ? Duration.zero : target);
          }
          if (!_controlsVisible && !_isDisposed) _controller?.setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaStop(key)) {
          debugPrint('[PlayerScreen] ⏹️ Media Stop key');
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }

        // D-pad / navigation keys: show controls if hidden, pass through if visible
        if (TvKeys.isNavigation(key)) {
          if (!_controlsVisible) {
            debugPrint('[PlayerScreen] 🚀 Showing controls');
            if (!_isDisposed) _controller?.setControlsVisibility(true);
            return KeyEventResult.handled;
          } else {
            // Safety: keep-alive the visibility timer.
            if (!_isDisposed) _controller?.setControlsVisibility(true);
          }
          return KeyEventResult.ignored;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _hasError 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'An error occurred',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          : _controller == null 
            ? const Center(child: CircularProgressIndicator())
            : BetterPlayer(controller: _controller!),
      ),
    );
  }
}
