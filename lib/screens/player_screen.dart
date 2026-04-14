import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/utils/tv_keys.dart';
import 'package:caffeine_tv/widgets/player_settings_overlay.dart';
import 'package:caffeine_tv/widgets/tv_player_controls.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:caffeine_tv/utils/wakelock_manager.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'dart:convert';
import 'package:caffeine_tv/services/subtitle_service.dart';
import 'package:caffeine_tv/widgets/language_picker_dialog.dart';
import 'package:caffeine_tv/models/sub_languages.dart';
import 'package:caffeine_tv/services/analytics_service.dart';

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
    this.externalSubtitles,
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
  final List<BetterPlayerSubtitlesSource>? externalSubtitles;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  final WatchHistoryService _historyService = WatchHistoryService();
  final SubtitleService _subtitleService = SubtitleService();
  final FocusNode _mainFocusNode = FocusNode();
  Timer? _saveTimer;
  Timer? _initWatchdogTimer;
  bool _controlsVisible = false;
  StreamSubscription? _visibilitySubscription;
  int _retryCount = 0;
  final ApiService _api = ApiService();
  bool _isRefreshing = false;
  bool _isDisposed = false;
  bool _isHandlingException = false;
  bool _hasInitialized = false; // Tracks if BetterPlayerEventType.initialized has fired
  Duration? _lastKnownPosition;
  DateTime? _loadStartTime;
  DateTime? _bufferingStartTime;
  DateTime? _sessionStartTime;

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
    WakelockManager.enable();
    _setupController();
    _startProgressTimer();

    _visibilitySubscription = _controller?.controlsVisibilityStream.listen((
      visible,
    ) {
      if (_controlsVisible != visible && mounted && !_isDisposed) {
        _safeSetState(() => _controlsVisible = visible);
      }
    });

    // Ensure we have focus on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();

      // Watchdog: The Chromecast Amlogic AVC decoder (c2.amlogic.avc.decoder) can
      // flush its pipeline during HLS initialization causing BetterPlayer to get stuck
      // decoding but never firing BetterPlayerEventType.initialized. A forced
      // setupDataSource() call kicks it into ExoPlayer STATE_READY.
      // Guard: skip if already initialized or if the exception handler is active
      // (to prevent a race condition between the watchdog and retry logic).
      _initWatchdogTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || _isDisposed || _hasInitialized || _isHandlingException) return;
        debugPrint('[PlayerScreen] ⚠️ Init watchdog fired — player not initialized after 3s, forcing reset');
        _forcePlayerReset();
      });
    });
  }

  Future<void> _autoDiscoverSubtitles() async {
    final useExternal = SettingsService().useExternalSubtitles;
    final langCode = SettingsService().language;
    final apiKey = SettingsService().opensubtitlesKey;

    debugPrint('[PlayerScreen] 🔍 Auto-discovery started (useExternal: $useExternal, language: $langCode, key: ${apiKey.isNotEmpty ? "YES" : "NO"})');

    if (!useExternal) return;
    if (_isSports || _isRefreshing || _isDisposed) return;
    if (langCode.isEmpty) return;

    final lang = supportedLanguages.firstWhere(
      (l) => l.languageCode == langCode,
      orElse: () => SubLanguages(languageName: '', languageCode: '', englishName: 'Unknown'),
    );

    final langName = lang.englishName;

    // 1. Check if we already have this language in externalSubtitles
    final existing = widget.externalSubtitles?.any((s) => s.name?.contains(langName) ?? false) ?? false;
    if (existing) {
       debugPrint('[PlayerScreen] ℹ️ Subtitles for $langName already present, skipping auto-discovery.');
       return;
    }

    // Robust ID extraction for Map and model types
    final dynamic rawId = widget.item is Map 
        ? (widget.item['id'] ?? widget.item['media_id'])
        : widget.item?.id;

    final int? tmdbId = rawId is int 
        ? rawId 
        : int.tryParse(rawId?.toString() ?? '');

    debugPrint('[PlayerScreen] 🔍 Extracted ID: $tmdbId (from raw: $rawId)');

    if (tmdbId == null || tmdbId == 0) {
      debugPrint('[PlayerScreen] ❌ Could not extract a valid TMDb ID, aborting auto-discovery.');
      return;
    }

    try {
      debugPrint('[PlayerScreen] 📡 Searching OpenSubtitles for $langName ($langCode)...');
      final downloadUrl = await _subtitleService.discoverBestSubtitle(
        tmdbId: tmdbId,
        languageCode: langCode,
        apiKey: apiKey,
        seasonNumber: widget.season,
        episodeNumber: widget.episode,
      );

      if (downloadUrl != null && !_isDisposed && mounted) {
        debugPrint('[PlayerScreen] ✅ Subtitle URL found: $downloadUrl');
        
        final newSource = BetterPlayerSubtitlesSource(
          name: '$langName (Auto)',
          urls: [downloadUrl],
          type: BetterPlayerSubtitlesSourceType.network,
        );

        // Merge with existing external subtitles
        final List<BetterPlayerSubtitlesSource> updatedExternalSubs = [
          ...widget.externalSubtitles ?? [],
          newSource,
        ];

        // Ensure uniqueness by name
        final Map<String, BetterPlayerSubtitlesSource> uniqueSubs = {};
        for (var sub in updatedExternalSubs) {
           if (sub.name != null) uniqueSubs[sub.name!] = sub;
        }
        final finalSubs = uniqueSubs.values.toList();

        final currentPosition = _controller?.videoPlayerController?.value.position ?? Duration.zero;
        final currentUrl = widget.url;

        debugPrint('[PlayerScreen] 🔄 Updating data source with ${finalSubs.length} subtitles...');

        // Only auto-setup if we are within the first 60 seconds of playback
        // Otherwise, it's too disruptive to restart the player.
        if (currentPosition.inSeconds > 60) {
          debugPrint('[PlayerScreen] ℹ️ Subtitles found too late in playback (>60s), skipping disruptive data source reset.');
          return;
        }

        // Re-setup data source with new subtitles but don't auto-activate
        await _controller?.setupDataSource(
          BetterPlayerDataSource(
            BetterPlayerDataSourceType.network,
            currentUrl,
            videoFormat: currentUrl.contains('m3u8') ||
                    currentUrl.contains('playlist') ||
                    currentUrl.contains('proxy/stream')
                ? BetterPlayerVideoFormat.hls
                : null,
            useAsmsTracks: true,
            useAsmsAudioTracks: true,
            useAsmsSubtitles: true,
            subtitles: finalSubs,
            preferredAudioLanguage: SettingsService().defaultAudioLanguage,
            headers: _getMergedHeaders(currentUrl, widget.referrer, widget.headers),
            bufferingConfiguration: const BetterPlayerBufferingConfiguration(
              minBufferMs: 30000,
              maxBufferMs: 60000,
              bufferForPlaybackMs: 3000,
              bufferForPlaybackAfterRebufferMs: 12000,
            ),
          ),
        );

        if (!_isDisposed && mounted) {
          _controller?.seekTo(currentPosition);
          _controller?.play();
          
          debugPrint('[PlayerScreen] ✅ Auto-subtitle "$langName (Auto)" added to menu.');
        }
      } else {
        debugPrint('[PlayerScreen] ℹ️ No suitable auto-subtitles found for TMDB ID $tmdbId, language: $langCode');
      }
    } catch (e) {
      debugPrint('[PlayerScreen] ❌ Auto-discovery error: $e');
    }
  }

  void _startProgressTimer() {
    _saveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveCurrentProgress();
    });
  }

  void _trackSessionEnd() {
    if (_sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
      if (duration > 0) {
        AnalyticsService.instance.trackEvent('Playback Session', {
          'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
          'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
          'name': widget.title,
          'duration_seconds': duration,
          'provider': widget.providerCode,
        });
      }
      _sessionStartTime = null;
    }
  }

  Future<void> _saveCurrentProgress({bool isFinished = false}) async {
    if (_controller == null || _controller!.videoPlayerController == null) {
      return;
    }

    final duration =
        _controller!.videoPlayerController!.value.duration ?? Duration.zero;
    if (duration == Duration.zero) {
      return;
    }

    // Capture the most reliable position. If the controller reports zero (often during 
    // error states or resets), fallback to the last progress event we captured.
    Duration position;
    if (isFinished) {
      position = duration;
    } else {
      final ctrlPos = _controller!.videoPlayerController!.value.position;
      position = (ctrlPos > Duration.zero) 
          ? ctrlPos 
          : (_lastKnownPosition ?? Duration.zero);
    }

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

    // --- SMART URL REWRITE ---
    // Only rewrite if videostr.net is the actual HOST, never inside encoded
    // query parameters (e.g. ?headers={"referer":"https://videostr.net/"})
    // which proxy servers like storm.vodvidl.site read to forward correct auth headers.
    var safeUrl = widget.url;
    try {
      final uri = Uri.parse(widget.url);
      if (uri.host == 'videostr.net' || uri.host.endsWith('.videostr.net')) {
        safeUrl = uri.replace(host: 'vidlink.pro').toString();
      }
    } catch (_) {}

    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        allowedScreenSleep: false, // Prevents race condition during source swap
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
          customControlsBuilder: (controller, onVisibilityChanged) =>
              TvPlayerControls(
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
        safeUrl,
        liveStream: _isSports, // Only actual live channels should use liveStream: true
        videoFormat:
            safeUrl.contains('m3u8') ||
                safeUrl.contains('playlist') ||
                safeUrl.contains('proxy/stream')
            ? BetterPlayerVideoFormat.hls
            : null,
        useAsmsTracks: true,
        useAsmsAudioTracks: true,
        useAsmsSubtitles: true,
        subtitles: widget.externalSubtitles,
        preferredAudioLanguage: SettingsService().defaultAudioLanguage,
        headers: _getMergedHeaders(safeUrl, widget.referrer, widget.headers),
        bufferingConfiguration: _getBufferingConfig(),
      ),
    );

    _loadStartTime = DateTime.now();
    AnalyticsService.instance.trackQoSEvent('Playback Attempt', {
      'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
      'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
      'name': widget.title,
      'url_host': Uri.tryParse(safeUrl)?.host,
    });
    debugPrint('[PlayerScreen] 📺 Playing: $safeUrl');
    debugPrint(
      '[PlayerScreen] 🔗 Referrer: ${widget.referrer ?? _getReferer(safeUrl)}',
    );

    _controller!.addEventsListener((event) async {
      if (_isDisposed) return;
      if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
        debugPrint(
          '[PlayerScreen] 🎉 Video finished, saving final progress (100%) and closing',
        );
        await _saveCurrentProgress(isFinished: true);
        if (mounted && !_isDisposed) Navigator.of(context).pop();
      } else if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        // Mark initialized so the watchdog does not fire and overlay hides
        _safeSetState(() {
          _hasInitialized = true;
        });
        _initWatchdogTimer?.cancel();
        _sessionStartTime = DateTime.now();

        if (_loadStartTime != null) {
          final loadTime = DateTime.now().difference(_loadStartTime!).inMilliseconds;
          AnalyticsService.instance.trackQoSEvent('Playback Loaded', {
            'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
            'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
            'load_time_ms': loadTime,
          });
          _loadStartTime = null;
        }

        // Try twice as tracks might load late in HLS manifest
        _selectPreferredAudioTrack();
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _selectPreferredAudioTrack(),
        );
        Future.delayed(
          const Duration(milliseconds: 4000),
          () => _selectPreferredAudioTrack(),
        );
      } else if (event.betterPlayerEventType == BetterPlayerEventType.bufferingStart) {
        _bufferingStartTime = DateTime.now();
        AnalyticsService.instance.trackQoSEvent('Buffering Start', {
          'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
          'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
        });
      } else if (event.betterPlayerEventType == BetterPlayerEventType.bufferingEnd) {
        if (_bufferingStartTime != null) {
          final bufferTime = DateTime.now().difference(_bufferingStartTime!).inMilliseconds;
          AnalyticsService.instance.trackQoSEvent('Buffering End', {
            'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
            'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
            'buffer_time_ms': bufferTime,
          });
          _bufferingStartTime = null;
        }
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.exception) {
        AnalyticsService.instance.trackQoSEvent('Playback Error', {
          'type': widget.isMovie ? 'movie' : (_isSports ? 'sports' : 'tv_show'),
          'id': widget.item is Map ? widget.item['id']?.toString() : widget.item?.id?.toString(),
          'error': event.parameters?['exception']?.toString(),
        });
        if (!_isDisposed) _handlePlayerException(event);
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.progress) {
        if (!_isDisposed) {
          final progress = event.parameters?['progress'] as Duration?;
          if (progress != null && 
              (_lastKnownPosition == null || (progress.inSeconds != _lastKnownPosition!.inSeconds))) {
              _lastKnownPosition = progress;
          }
        }
      }
    });
  }

  bool get _isSports =>
      !widget.isMovie && (widget.season == null || widget.episode == null);

  void _handlePlayerException(BetterPlayerEvent event) async {
    if (_isHandlingException || _isRefreshing || _isDisposed) return;
    _isHandlingException = true;

    final exception = event.parameters?['exception'];
    debugPrint('[PlayerScreen] ⚠️ Playback exception: $exception');

    // Only retry for network/source errors, especially if we've been playing for a while
    // or if the error code suggests a source issue (2001, 2002)
    final errorStr = exception?.toString().toLowerCase() ?? '';
    
    // Specific HLS Live errors
    final isBehindLiveWindow = errorStr.contains('behindlivewindowexception');
    final isPlaylistStuck = errorStr.contains('playliststuckexception');

    final isSourceError =
        isBehindLiveWindow ||
        isPlaylistStuck ||
        errorStr.contains('source error') ||
        errorStr.contains('httpdatasource') ||
        errorStr.contains('sockettimeout') ||
        errorStr.contains('unexpected end of stream');

    // 403 = IP-locked / auth error — retrying the same URL is pointless, skip straight to fallback
    final is403 =
        errorStr.contains('403') ||
        errorStr.contains('forbidden') ||
        errorStr.contains('invalidresponsecodeexception');

    if (isBehindLiveWindow || isPlaylistStuck) {
      AnalyticsService.instance.trackQoSEvent('HLS Recovery Attempt', {
        'error_type': isBehindLiveWindow ? 'BehindLiveWindow' : 'PlaylistStuck',
        'url': widget.url,
      });
      debugPrint('[PlayerScreen] 🔄 Recovering from HLS specific error: $errorStr');
    }

    if (is403) {
      debugPrint(
        '[PlayerScreen] 🚫 403 Forbidden — IP-locked URL, skipping retries, falling back...',
      );
      _isHandlingException = false;
      await _fallbackToNextProvider();
      return;
    }

    if (isSourceError && _retryCount < 3) {
      _retryCount++;
      debugPrint(
        '[PlayerScreen] 🔄 Attempting to re-fetch stream URL (Retry $_retryCount/3)...',
      );

      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _isRefreshing = true;
          _hasError = false;
        });
      }

      try {
        final currentPosition =
            _lastKnownPosition ??
            _controller?.videoPlayerController?.value.position ??
            widget.startPosition ??
            Duration.zero;

        String? newUrl;
        String? newReferrer;
        Map<String, String>? newHeaders;

        if (_isSports) {
          // Special refresh logic for sports: re-query Supabase
          final refreshResult = await _refreshSportsStream();
          if (refreshResult != null && !_isDisposed) {
            newUrl = refreshResult['url'] as String?;
            newReferrer = refreshResult['referrer'] as String?;
            
            // Update mirrors if they improved
            if (refreshResult['sources'] != null && 
                refreshResult['sources'] is List && 
                widget.allProviders != null) {
               // Update our local state if we want to refresh the mirrors list
               // For now, at least we have the new main URL.
            }
          }
        } else {
          // Robust ID access for both MovieDetail/TvShowDetail objects and Map objects
          final dynamic rawId = widget.item is Map
              ? (widget.item['media_id'] ?? widget.item['id'])
              : widget.item?.id;

          final int? mediaId = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '');

          if (mediaId == null) {
            debugPrint(
              '[PlayerScreen] ❌ Cannot retry: mediaId is null or invalid ($rawId)',
            );
            _isHandlingException = false;
            _safeSetState(() => _isRefreshing = false);
            return;
          }

          final core.ProviderStreamResponse response;
          if (widget.isMovie) {
            response = await _api.fetchMovieStream(
              mediaId,
              provider: widget.providerCode ?? 'vidlink',
            );
          } else {
            response = await _api.fetchTvStream(
              mediaId,
              widget.season!,
              widget.episode!,
              provider: widget.providerCode ?? 'vidlink',
            );
          }

          if (response.success &&
              response.links != null &&
              response.links!.isNotEmpty) {
            newUrl = response.links!.first.url;
            newHeaders = response.links!.first.headers;
          }
        }

        if (newUrl != null && newUrl.isNotEmpty) {
          debugPrint('[PlayerScreen] ✅ Re-fetched new URL: $newUrl');

          if (!mounted) return;

          // Small delay to allow network to settle before retrying
          await Future.delayed(const Duration(seconds: 2));
          if (_isDisposed || !mounted) return;

          // Seek to the last known position after initialization
          late Function(BetterPlayerEvent) refreshListener;
          refreshListener = (refreshEvent) {
            if (refreshEvent.betterPlayerEventType ==
                BetterPlayerEventType.initialized) {
              _controller?.seekTo(currentPosition);
              _controller?.play();
              _controller?.removeEventsListener(refreshListener);
              // Reset flag so future exceptions can be handled
              _isHandlingException = false;
            }
          };
          _controller?.addEventsListener(refreshListener);

          // Re-initialize the player with the new URL and the current position
          await _controller?.setupDataSource(
            BetterPlayerDataSource(
              BetterPlayerDataSourceType.network,
              newUrl,
              videoFormat:
                  newUrl.contains('m3u8') ||
                      newUrl.contains('playlist') ||
                      newUrl.contains('proxy/stream')
                  ? BetterPlayerVideoFormat.hls
                  : null,
              useAsmsTracks: true,
              useAsmsAudioTracks: true,
              useAsmsSubtitles: true,
              preferredAudioLanguage: SettingsService().defaultAudioLanguage,
              headers: _getMergedHeaders(
                newUrl,
                newReferrer ?? widget.referrer,
                newHeaders,
              ),
              bufferingConfiguration: _getBufferingConfig(),
            ),
          );

          if (!_isDisposed && mounted) {
            _controller?.play();
            // Only seek to live edge for actual live/sports content.
            // VOD HLS content (movies/shows that use m3u8) must resume from
            // the saved position, not restart from the beginning.
            if (_isSports) {
              debugPrint('[PlayerScreen] 🎯 Recovery: Seeking to live edge (0)');
              _controller?.seekTo(Duration.zero);
            } else if (currentPosition > Duration.zero) {
              debugPrint('[PlayerScreen] ⏩ Recovery: Restoring position to ${currentPosition.inSeconds}s');
              _controller?.seekTo(currentPosition);
            }
            _safeSetState(() => _isRefreshing = false);
          }
        } else {
          debugPrint('[PlayerScreen] ❌ Re-fetch failed or returned no links');
          _isHandlingException = false;
          _safeSetState(() => _isRefreshing = false);
          if (widget.isMovie || widget.episode != null) {
            // Automatically try another provider if re-fetch failed
            await _fallbackToNextProvider();
          } else {
            _safeSetState(() {
              _hasError = true;
              _errorMessage =
                  'Failed to refresh stream. Please try again later.';
            });
          }
        }
      } catch (e) {
        debugPrint('[PlayerScreen] ❌ Error during refresh: $e');
        _isHandlingException = false;
        _safeSetState(() => _isRefreshing = false);
      }
    } else {
      debugPrint('[PlayerScreen] ❌ Max retries reached or non-source error');
      _isHandlingException = false;
      _safeSetState(() => _isRefreshing = false);
      if (isSourceError && (widget.isMovie || widget.episode != null)) {
        // Source kept failing after retries — try next provider automatically
        await _fallbackToNextProvider();
      } else {
        _safeSetState(() {
          _hasError = true;
          _errorMessage = exception?.toString() ?? 'Playback error';
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _refreshSportsStream() async {
    try {
      final String? eventId = widget.item is Map
          ? widget.item['id']?.toString()
          : null;
      if (eventId == null) return null;

      debugPrint(
        '[PlayerScreen] 🔄 Querying Supabase for fresh sports stream (ID: $eventId)...',
      );
      final response = await Supabase.instance.client
          .from('live_streams')
          .select('video_url, referrer, sources')
          .eq('id', eventId)
          .maybeSingle();

      if (response != null &&
          response['video_url'] != null &&
          response['video_url'].isNotEmpty) {
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
    debugPrint(
      '[PlayerScreen] 🎧 Attempting to select audio track: $preferred',
    );

    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      final label = track.label?.toLowerCase() ?? '';
      debugPrint('[PlayerScreen]   - Track: lang="$lang", label="$label"');

      final isMatch =
          lang == preferred ||
          lang.startsWith(preferred) ||
          label.startsWith(preferred) ||
          label.contains(preferred) ||
          (preferred == 'en' && label.contains('english'));

      if (isMatch) {
        debugPrint(
          '[PlayerScreen] ✅ Match found! Selecting track: $label ($lang)',
        );
        _controller!.setAudioTrack(track);
        return;
      }
    }
  }

  String _getReferer(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.isEmpty || uri.host.isEmpty) return '';
      // Most CDNs (vixsrc, vidlink, vidsrc) require the trailing slash on Referer
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return '';
    }
  }

  String _getOrigin(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.isEmpty || uri.host.isEmpty)
        return url.replaceAll(RegExp(r'/$'), '');
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url.replaceAll(RegExp(r'/$'), '');
    }
  }

  Map<String, String> _getMergedHeaders(
    String url,
    String? referrer,
    Map<String, String>? extra,
  ) {
    // Standard headers for all requests
    final Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-Dest': 'empty',
    };

    // Helper to normalize keys to TitleCase for common headers to prevent duplicates
    String normalizeKey(String key) {
      final k = key.toLowerCase();
      if (k == 'referer' || k == 'referrer') return 'Referer';
      if (k == 'origin') return 'Origin';
      if (k == 'user-agent') return 'User-Agent';
      if (k == 'accept') return 'Accept';
      if (k == 'connection') return 'Connection';
      return key;
    }

    // Helper to strip trailing slashes from URL-like header values
    String stripTrailingSlash(String value) {
      return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    }

    // Merge extra headers first; strip trailing slashes from URL-like headers
    if (extra != null) {
      for (final entry in extra.entries) {
        final normalizedKey = normalizeKey(entry.key);
        // CRITICAL: Relax Referer normalization. While Origin must NEVER have a trailing slash,
        // Referer SHOULD have one when pointing to a root domain for many CDNs (Vixsrc/VidLink).
        final value = (normalizedKey == 'Origin')
            ? stripTrailingSlash(entry.value)
            : entry.value;
        headers[normalizedKey] = value;
      }
    }

    // Add default Referer and Origin if not already set by extra
    final effectiveReferrer = referrer ?? _getReferer(url);
    if (effectiveReferrer.isNotEmpty) {
      if (!headers.containsKey('Referer')) {
        headers['Referer'] = effectiveReferrer;
      }
      // CRITICAL: Many CDNs (VidLink, justhd.tv) use strict Origin/Referer matching
      // as a form of basic anti-bot. If Referer is set, Origin MUST follow.
      if (!headers.containsKey('Origin')) {
        headers['Origin'] = _getOrigin(effectiveReferrer);
      }
    } else {
      // Fallback: use a generic Origin if the Referer is missing but we're in HLS
      if (!headers.containsKey('Origin')) {
        headers['Origin'] = 'https://vidlink.pro';
      }
    }

    // Extract headers from URL query if present (as a final override)
    // This is crucial for proxy URLs that encode their required headers in the query string.
    try {
      final uri = Uri.parse(url);
      final encodedHeaders = uri.queryParameters['headers'];
      if (encodedHeaders != null) {
        final decoded = jsonDecode(encodedHeaders);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            headers[normalizeKey(k.toString())] = v.toString();
          });
        }
      }
    } catch (_) {
      // Ignore parsing errors
    }

    // --- PROXY AUTH OVERRIDE ---
    // The ?headers= query params are instructions for the PROXY to use when
    // fetching from upstream CDNs — they are NOT client-to-proxy auth headers.
    // The proxy itself requires vidlink.pro Origin/Referer from the client.
    if (url.contains('storm.vodvidl.site') || url.contains('vidlink')) {
      headers['Referer'] = 'https://vidlink.pro/';
      headers['Origin'] = 'https://vidlink.pro';
    }

    if (url.contains('vixsrc.to') || url.contains('vixsrc')) {
      headers['Referer'] = 'https://vixsrc.to';
      headers['Origin'] = 'https://vixsrc.to';
    }

    // Log final resolved headers for debugging proxy issues
    debugPrint('[PlayerScreen] 🔑 Final headers for ${Uri.tryParse(url)?.host}: '
        'Referer=${headers['Referer']}, Origin=${headers['Origin']}');

    return headers;
  }

  Future<void> _fallbackToNextProvider() async {
    _trackSessionEnd();
    await _saveCurrentProgress();
    if (_isDisposed || !mounted) return;

    // Capture current position and save it to history before switching
    await _saveCurrentProgress();
    final currentPos = _controller?.videoPlayerController?.value.position ?? _lastKnownPosition;

    if (widget.allProviders == null || widget.allProviders!.isEmpty) {
      debugPrint('[PlayerScreen] ❌ No provider list for auto-fallback');
      _showSettings(); // Manual selection
      return;
    }

    final currentIndex = widget.allProviders!.indexWhere(
      (p) => p['code'] == widget.providerCode,
    );
    final nextIndex = currentIndex + 1;

    if (nextIndex < widget.allProviders!.length) {
      final nextProvider = widget.allProviders![nextIndex];
      final nextProviderCode = nextProvider['code']!;

      debugPrint(
        '[PlayerScreen] 🔄 Auto-falling back to next provider: $nextProviderCode',
      );

      if (mounted && !_isDisposed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => _buildVideoLoader(nextProviderCode, currentPos),
          ),
        );
      }
    } else {
      debugPrint('[PlayerScreen] ❌ All providers exhausted for auto-fallback');
      _showSettings(); // Show picker as last resort
    }
  }

  void _showSettings() {
    if (_controller == null) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => PlayerSettingsOverlay(
        controller: _controller!,
        currentProvider: widget.providerCode,
        allProviders: widget.allProviders,
        providerLabel: _isSports ? 'Select Mirror' : 'Server (Provider)',
        onSearchMore: _searchMoreSubtitles,
        onChangeProvider: (newProviderCode) async {
          if (!mounted) return;
          // Close settings dialog
          Navigator.of(context).pop();

          // Save current position before switching
          await _saveCurrentProgress();
          if (!mounted || _isDisposed) return;
          
          final currentPos = _controller?.videoPlayerController?.value.position ?? _lastKnownPosition;

          debugPrint(
            '[PlayerScreen] 🔄 Changing provider to: $newProviderCode',
          );

          if (_isSports && widget.allProviders != null) {
            // Check if newProviderCode is one of our mirror URLs
            final source = widget.allProviders!.firstWhere(
              (p) => p['code'] == newProviderCode,
              orElse: () => {},
            );

            if (source.isNotEmpty) {
              debugPrint(
                '[PlayerScreen] ⚾ Sports mirror switch to: $newProviderCode',
              );
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

          if (mounted && !_isDisposed) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    _buildVideoLoader(newProviderCode, currentPos),
              ),
            );
          }
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

  Future<void> _searchMoreSubtitles(String langCode) async {
    final int? tmdbId = widget.item is Map 
        ? (widget.item['id'] ?? widget.item['media_id'])
        : widget.item?.id;

    if (tmdbId == null) {
      debugPrint('[PlayerScreen] ❌ TMDB ID is null, cannot search subtitles');
      return;
    }

    _safeSetState(() {
      _isRefreshing = true;
    });

    try {
      final searchResults = await _subtitleService.searchSubtitles(
        tmdbId: tmdbId,
        languageCode: langCode,
        apiKey: SettingsService().opensubtitlesKey,
        seasonNumber: widget.season,
        episodeNumber: widget.episode,
      );

      if (searchResults.isNotEmpty) {
        debugPrint('[PlayerScreen] ✅ Found ${searchResults.length} new subtitles');
        
        final List<BetterPlayerSubtitlesSource> newSubs = [];
        final langName = supportedLanguages
            .firstWhere((l) => l.languageCode == langCode,
                orElse: () => SubLanguages(languageName: '', languageCode: '', englishName: 'Unknown'))
            .englishName;

        for (var data in searchResults) {
          final fileId = data.attr?.files?.first.fileId;
          if (fileId != null) {
            final downloadUrl = await _subtitleService.downloadSubtitle(
              fileId,
              SettingsService().opensubtitlesKey,
            );
            if (downloadUrl != null) {
              newSubs.add(
                BetterPlayerSubtitlesSource(
                  name: '$langName (OS)',
                  urls: [downloadUrl],
                  type: BetterPlayerSubtitlesSourceType.network,
                ),
              );
            }
          }
        }

        if (newSubs.isEmpty) {
          debugPrint('[PlayerScreen] ❌ Failed to download any new subtitles');
          return;
        }

        // Merge with existing external subtitles if any
        final List<BetterPlayerSubtitlesSource> updatedExternalSubs = [
          ...widget.externalSubtitles ?? [],
          ...newSubs,
        ];

        // Unique filter to avoid duplicates
        final Map<String, BetterPlayerSubtitlesSource> uniqueSubs = {};
        for (var sub in updatedExternalSubs) {
           // Use name as key, might want to be more specific if possible
           uniqueSubs[sub.name!] = sub;
        }

        final finalSubs = uniqueSubs.values.toList();

        final currentPosition = _controller?.videoPlayerController?.value.position ?? Duration.zero;
        final currentUrl = widget.url;

        // Re-setup data source with new subtitles
        await _controller?.setupDataSource(
          BetterPlayerDataSource(
            BetterPlayerDataSourceType.network,
            currentUrl,
            videoFormat: currentUrl.contains('m3u8') ||
                    currentUrl.contains('playlist') ||
                    currentUrl.contains('proxy/stream')
                ? BetterPlayerVideoFormat.hls
                : null,
            useAsmsTracks: true,
            useAsmsAudioTracks: true,
            useAsmsSubtitles: true,
            subtitles: finalSubs,
            preferredAudioLanguage: SettingsService().defaultAudioLanguage,
            headers: _getMergedHeaders(currentUrl, widget.referrer, widget.headers),
            bufferingConfiguration: const BetterPlayerBufferingConfiguration(
              minBufferMs: 30000,
              maxBufferMs: 60000,
              bufferForPlaybackMs: 3000,
              bufferForPlaybackAfterRebufferMs: 12000,
            ),
          ),
        );

        _controller?.seekTo(currentPosition);
        _controller?.play();
      } else {
         debugPrint('[PlayerScreen] ℹ️ No subtitles found for language: $langCode');
      }
    } catch (e) {
      debugPrint('[PlayerScreen] ❌ Error searching more subtitles: $e');
    } finally {
      _safeSetState(() {
        _isRefreshing = false;
      });
    }
  }

  /// Forces a setupDataSource() reset to recover from the Chromecast Amlogic
  /// codec flush bug where the player gets stuck in buffering without ever
  /// firing BetterPlayerEventType.initialized.
  Future<void> _forcePlayerReset() async {
    if (_controller == null || _isDisposed || !mounted) return;
    
    // Capture current position BEFORE reset so we can restore it
    await _saveCurrentProgress();
    final currentPosition = _controller?.videoPlayerController?.value.position ?? _lastKnownPosition;

    debugPrint('[PlayerScreen] 🔄 Forcing player reset via setupDataSource... '
        '(saving position: ${currentPosition?.inSeconds}s)');
    try {
    // Smart host-only rewrite — preserve encoded query params intact
    var safeUrl = widget.url;
    try {
      final uri = Uri.parse(widget.url);
      if (uri.host == 'videostr.net' || uri.host.endsWith('.videostr.net')) {
        safeUrl = uri.replace(host: 'vidlink.pro').toString();
      }
    } catch (_) {}

      await _controller?.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          safeUrl,
          liveStream: _isSports, // Only actual live channels should use liveStream: true
          videoFormat:
              safeUrl.contains('m3u8') ||
                  safeUrl.contains('playlist') ||
                  safeUrl.contains('proxy/stream')
              ? BetterPlayerVideoFormat.hls
              : null,
          useAsmsTracks: true,
          useAsmsAudioTracks: true,
          useAsmsSubtitles: true,
          subtitles: widget.externalSubtitles,
          preferredAudioLanguage: SettingsService().defaultAudioLanguage,
          headers: _getMergedHeaders(safeUrl, widget.referrer, widget.headers),
          bufferingConfiguration: _getBufferingConfig(),
        ),
      );

      if (!_isDisposed && mounted) {
        _controller?.play();
        // Restore the CURRENT position (not just the initial startPosition)
        final resumePos = currentPosition ?? widget.startPosition;
        if (resumePos != null && resumePos > Duration.zero) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_isDisposed && mounted) {
            _controller?.seekTo(resumePos);
            debugPrint('[PlayerScreen] ⏩ Restored position to ${resumePos.inSeconds}s');
          }
        }
        debugPrint('[PlayerScreen] ✅ Forced reset complete, playback started');
      }
    } catch (e) {
      debugPrint('[PlayerScreen] ❌ Error during forced reset: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _trackSessionEnd();
    _saveTimer?.cancel();
    _initWatchdogTimer?.cancel();
    _saveCurrentProgress(); // Best effort save
    _visibilitySubscription?.cancel();
    WakelockManager.disable();

    // Safety check before controller methods
    try {
      _controller?.pause();
      _controller?.dispose();
    } catch (e) {
      debugPrint('[PlayerScreen] Error during controller disposal: $e');
    }

    _mainFocusNode.dispose();
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
        debugPrint(
          '[PlayerScreen] 🔑 key: ${key.debugName}, controlsVisible: $_controlsVisible',
        );

        // Back / Exit
        if (TvKeys.isBack(key)) {
          _saveCurrentProgress().then((_) {
            if (mounted) Navigator.of(context).pop();
          });
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
          if (!_controlsVisible && !_isDisposed)
            _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaFastForward(key)) {
          debugPrint('[PlayerScreen] ⏩ Media Fast Forward key');
          final pos = _controller?.videoPlayerController?.value.position;
          if (pos != null) {
            _controller?.seekTo(pos + const Duration(seconds: 10));
          }
          if (!_controlsVisible && !_isDisposed)
            _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaRewind(key)) {
          debugPrint('[PlayerScreen] ⏪ Media Rewind key');
          final pos = _controller?.videoPlayerController?.value.position;
          if (pos != null) {
            final target = pos - const Duration(seconds: 10);
            _controller?.seekTo(
              target < Duration.zero ? Duration.zero : target,
            );
          }
          if (!_controlsVisible && !_isDisposed)
            _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaStop(key)) {
          debugPrint('[PlayerScreen] ⏹️ Media Stop key');
          _saveCurrentProgress().then((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return KeyEventResult.handled;
        }

        // D-pad / navigation keys: show controls if hidden, pass through if visible
        if (TvKeys.isNavigation(key)) {
          if (!_controlsVisible) {
            debugPrint('[PlayerScreen] 🚀 Showing controls');
            _setControlsVisibility(true);
          } else {
            // Safety: keep-alive the visibility timer.
            _setControlsVisibility(true);
          }
          return KeyEventResult.ignored;
        }

        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }
          await _saveCurrentProgress();
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage ?? 'An error occurred',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                        ),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    _controller == null
                        ? const SizedBox.shrink()
                        : BetterPlayer(controller: _controller!),
                    // Loading overlay: stays in the tree to allow for the fade-out
                    // animation when _hasInitialized becomes true.
                    _buildLoadingOverlay(),
                  ],
                ),
        ),
      ),
    );
  }

  /// Returns the TMDB image URL for the backdrop (landscape) if available,
  /// falling back to poster (portrait). Used as the loading screen background.
  String? get _posterUrl {
    try {
      const base = 'https://image.tmdb.org/t/p/w1280';
      final item = widget.item;
      if (item == null) return null;
      // Prefer backdrop (landscape) for the fullscreen loading look
      final backdrop = item.backdropPath as String?;
      if (backdrop != null && backdrop.isNotEmpty) return '$base$backdrop';
      final poster = item.posterPath as String?;
      if (poster != null && poster.isNotEmpty) return '$base$poster';
    } catch (_) {}
    return null;
  }

  Widget _buildLoadingOverlay() {
    final imageUrl = _posterUrl;
    return IgnorePointer(
      ignoring: _hasInitialized,
      child: AnimatedOpacity(
        opacity: _hasInitialized ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        child: Container(
          color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop / poster image
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            // Dark gradient overlay so the spinner is readable
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            // Title + spinner at the bottom
            Positioned(
              left: 48,
              right: 48,
              bottom: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!widget.isMovie && widget.season != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Season ${widget.season}  •  Episode ${widget.episode}'
                        '${widget.episodeName != null ? "  •  ${widget.episodeName}" : ""}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading…',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  BetterPlayerBufferingConfiguration _getBufferingConfig() {
    if (_isSports) {
      // Aggressive buffering for live manifests with short windows (standard IPTV)
      return const BetterPlayerBufferingConfiguration(
        minBufferMs: 2500, // 2.5 seconds (allocate up to)
        maxBufferMs: 15000, // 15 seconds max memory footprint
        bufferForPlaybackMs: 500, // Start playing at 0.5s to minimize latency
        bufferForPlaybackAfterRebufferMs: 1000, // Recover fast if dropped
      );
    }
    return const BetterPlayerBufferingConfiguration(
      minBufferMs: 30000, // Target 30s of buffered data ahead
      maxBufferMs: 60000, // Allow up to 60s buffer ceiling (reduced from 90s to save memory)
      bufferForPlaybackMs: 3000, // Start playing after 3s
      bufferForPlaybackAfterRebufferMs: 12000, // Resume after 12s on rebuffer (was 5s!)
    );
  }

  void _setControlsVisibility(bool visible) {
    if (_isDisposed || !mounted || _controller == null) return;
    try {
      _controller?.setControlsVisibility(visible);
    } catch (e) {
      debugPrint('[PlayerScreen] ⚠️ Failed to set controls visibility: $e');
    }
  }
}
