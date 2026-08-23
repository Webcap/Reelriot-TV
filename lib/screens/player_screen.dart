import 'package:flutter/material.dart';
import 'package:reelriot_tv/services/outage_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/player_settings_overlay.dart';
import 'package:reelriot_tv/widgets/tv_player_controls.dart';
import 'package:reelriot_tv/screens/video_loader_screen.dart';
import 'package:reelriot_tv/utils/wakelock_manager.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'dart:convert';
import 'package:reelriot_tv/services/subtitle_service.dart';
import 'package:reelriot_tv/widgets/language_picker_dialog.dart';
import 'package:reelriot_tv/models/sub_languages.dart';
import 'package:reelriot_tv/services/analytics_service.dart';
import 'package:reelriot_tv/env.dart';

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
    this.quality,
    this.headers,
    this.externalSubtitles,
    this.nextEpisode,
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
  final String? quality;
  final Map<String, String>? headers;
  final List<CaffeinePlayerSubtitlesSource>? externalSubtitles;
  final Map<String, dynamic>? nextEpisode;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  CaffeinePlayerController? _controller;
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
  bool _hasInitialized =
      false; // Tracks if BetterPlayerEventType.initialized has fired
  Duration? _lastKnownPosition;
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
    _lastKnownPosition = widget.startPosition;
    WakelockManager.enable();
    OutageService.instance.pause();
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

      // Watchdog: The Chromecast Amlogic AVC decoder can stall during initialization.
      // We relax this to 15s for all media types to ensure the hardware decoder has 
      // enough time to handshake and report dimensions (width > 0).
      _initWatchdogTimer = Timer(const Duration(seconds: 15), () {
        if (!mounted || _isDisposed || _hasInitialized || _isHandlingException) {
          return;
        }
        debugPrint(
          '[PlayerScreen] ⚠️ Init watchdog fired — player not initialized after 15s, forcing reset',
        );
        _forcePlayerReset();
      });
    });
  }

  Future<void> _autoDiscoverSubtitles() async {
    final useExternal = SettingsService().useExternalSubtitles;
    final langCode = SettingsService().language;
    final apiKey = SettingsService().opensubtitlesKey;

    debugPrint(
      '[PlayerScreen] 🔍 Auto-discovery started (useExternal: $useExternal, language: $langCode, key: ${apiKey.isNotEmpty ? "YES" : "NO"})',
    );

    if (!useExternal) return;
    if (_isSports || _isRefreshing || _isDisposed) return;
    if (langCode.isEmpty) return;

    final lang = supportedLanguages.firstWhere(
      (l) => l.languageCode == langCode,
      orElse: () => SubLanguages(
        languageName: '',
        languageCode: '',
        englishName: 'Unknown',
      ),
    );

    final langName = lang.englishName;

    // 1. Check if we already have this language in externalSubtitles
    final existing =
        widget.externalSubtitles?.any(
          (s) => s.name?.contains(langName) ?? false,
        ) ??
        false;
    if (existing) {
      debugPrint(
        '[PlayerScreen] ℹ️ Subtitles for $langName already present, skipping auto-discovery.',
      );
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
      debugPrint(
        '[PlayerScreen] ❌ Could not extract a valid TMDb ID, aborting auto-discovery.',
      );
      return;
    }

    try {
      debugPrint(
        '[PlayerScreen] 📡 Searching OpenSubtitles for $langName ($langCode)...',
      );
      final downloadUrl = await _subtitleService.discoverBestSubtitle(
        tmdbId: tmdbId,
        languageCode: langCode,
        apiKey: apiKey,
        seasonNumber: widget.season,
        episodeNumber: widget.episode,
      );

      if (downloadUrl != null && !_isDisposed && mounted) {
        debugPrint('[PlayerScreen] ✅ Subtitle URL found: $downloadUrl');

        final newSource = CaffeinePlayerSubtitlesSource(
          name: '$langName (Auto)',
          url: downloadUrl,
        );

        // Merge with existing external subtitles
        final List<CaffeinePlayerSubtitlesSource> updatedExternalSubs = [
          ...widget.externalSubtitles ?? [],
          newSource,
        ];

        // Ensure uniqueness by name
        final Map<String, CaffeinePlayerSubtitlesSource> uniqueSubs = {};
        for (var sub in updatedExternalSubs) {
          if (sub.name != null) uniqueSubs[sub.name!] = sub;
        }
        final finalSubs = uniqueSubs.values.toList();

        final currentPosition = _controller?.position ?? Duration.zero;

        debugPrint(
          '[PlayerScreen] 🔄 Updating data source with ${finalSubs.length} subtitles...',
        );

        // Only auto-setup if we are within the first 60 seconds of playback
        if (currentPosition.inSeconds > 60) {
          debugPrint(
            '[PlayerScreen] ℹ️ Subtitles found too late in playback (>60s), skipping disruptive data source reset.',
          );
          return;
        }

        // Directly activate auto-discovered subtitle track without stream reset
        final autoTrack = SubtitleTrack.uri(
          downloadUrl,
          title: '$langName (Auto)',
        );
        _controller?.setSubtitleTrack(autoTrack);

        debugPrint(
          '[PlayerScreen] ✅ Auto-subtitle "$langName (Auto)" activated.',
        );
      } else {
        debugPrint(
          '[PlayerScreen] ℹ️ No suitable auto-subtitles found for TMDB ID $tmdbId, language: $langCode',
        );
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
          'id': widget.item is Map
              ? widget.item['id']?.toString()
              : widget.item?.id?.toString(),
          'name': widget.title,
          'duration_seconds': duration,
          'provider': widget.providerCode,
        });
      }
      _sessionStartTime = null;
    }
  }

  Future<void> _saveCurrentProgress({bool isFinished = false}) async {
    if (_controller == null) {
      return;
    }

    final duration = _controller!.duration;
    // Skip saving progress for live sports or if duration is invalid
    if (_isSports || duration == Duration.zero) {
      return;
    }

    Duration position;
    if (isFinished) {
      position = duration;
    } else {
      final ctrlPos = _controller!.position;
      position = (ctrlPos > const Duration(seconds: 5))
          ? ctrlPos
          : (_lastKnownPosition != null && _lastKnownPosition! > const Duration(seconds: 5)
              ? _lastKnownPosition!
              : (widget.startPosition ?? Duration.zero));
    }

    // Do NOT overwrite valid saved history with near-zero initial loading positions
    if (!isFinished &&
        position <= const Duration(seconds: 5) &&
        widget.startPosition != null &&
        widget.startPosition! > const Duration(seconds: 5)) {
      debugPrint(
        '[PlayerScreen] 🛡️ Preserving saved resume position (${widget.startPosition}), skipping startup 0s progress save.',
      );
      return;
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
    final lowerUrl = widget.url.toLowerCase();
    if (widget.url.isEmpty ||
        lowerUrl.contains('/embed/') ||
        lowerUrl.contains('web.nxsha.app') ||
        lowerUrl.contains('vidsrcme.ru/embed')) {
      debugPrint('[PlayerScreen] ❌ Non-playable HTML embed URL detected: ${widget.url}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          _fallbackToNextProvider();
        }
      });
      return;
    }

    // --- SMART URL REWRITE ---
    // 1. Decode HTML entities if they slipped through (common in scraped sports links)
    var safeUrl = widget.url.replaceAll('&amp;', '&');
    var headers = _getMergedHeaders(safeUrl, widget.referrer, widget.headers);

    // 2. Only rewrite if videostr.net is the actual HOST
    try {
      final uri = Uri.parse(safeUrl);
      debugPrint('[PlayerScreen] 🔍 Parsed Host: "${uri.host}" for URL: "$safeUrl"');
      if (uri.host == 'videostr.net' || uri.host.endsWith('.videostr.net')) {
        safeUrl = uri.replace(host: 'vidlink.pro').toString();
        // Refresh headers for the new host
        headers = _getMergedHeaders(safeUrl, widget.referrer, widget.headers);
      }
      
      // 3. For instreams.live and wfty.st, we often need the proxy immediately because of IP-locking
      if (uri.host.contains('instreams.live') || uri.host.contains('wfty.st')) {
        debugPrint('[PlayerScreen] 🛡️ Known IP-locked domain (${uri.host}), using proxy fallback');
        // We use the headers meant for the UPSTREAM to build the proxied URL
        safeUrl = _buildProxiedUrl(safeUrl, headers);
        
        // CRITICAL: When hitting our proxy, we should NOT send the target headers 
        // (like Origin: instreams.click) to our own proxy server, as that will 
        // trigger CORS blocks. The proxy will use them for its upstream request.
        headers = {
          'User-Agent': headers['User-Agent'] ?? '',
          'Accept': '*/*',
        };
      }
    } catch (e, stack) {
      debugPrint('[PlayerScreen] ❌ Rewrite error: $e\n$stack');
    }

    _controller = CaffeinePlayerController();
    
    // Set metadata for controls
    _controller!.name = widget.title;
    if (!widget.isMovie && widget.season != null) {
      _controller!.watchingText = 'Season ${widget.season} • Episode ${widget.episode}'
          '${widget.episodeName != null ? " • ${widget.episodeName}" : ""}';
    } else if (widget.item is Map) {
      _controller!.watchingText = widget.item['release_date']?.split('-')[0] ?? '';
    }

    debugPrint('[PlayerScreen] 📺 Playing (media_kit): $safeUrl');

    _controller!.addEventsListener((event) async {
      if (_isDisposed) return;
      
      // LOG EVERY EVENT FOR DEBUGGING (skip progress to avoid spam)
      if (event.type != CaffeinePlayerEventType.progress) {
        debugPrint('[PlayerScreen] 🔔 Player Event: ${event.type}${event.message != null ? " (${event.message})" : ""}');
      }

      if (event.type == CaffeinePlayerEventType.finished) {
        debugPrint(
          '[PlayerScreen] 🎉 Video finished, saving final progress (100%) and closing',
        );
        await _saveCurrentProgress(isFinished: true);
        if (mounted && !_isDisposed) Navigator.of(context).pop();
      } else if (event.type == CaffeinePlayerEventType.initialized) {
        _safeSetState(() {
          _hasInitialized = true;
          debugPrint('[PlayerScreen] ✅ State updated: _hasInitialized = true. Overlay should fade.');
        });
        _initWatchdogTimer?.cancel();
        _sessionStartTime = DateTime.now();

        // Try twice as tracks might load late
        _selectPreferredAudioTrack();
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _selectPreferredAudioTrack(),
        );
      } else if (event.type == CaffeinePlayerEventType.error) {
        debugPrint('[PlayerScreen] ❌ RECEIVED ERROR: ${event.message}');
        _handleException(event.message ?? 'Unknown error');
      } else if (event.type == CaffeinePlayerEventType.progress) {
        if (!_isDisposed) {
          final progress = event.position;
          if (progress != null && progress > const Duration(seconds: 5)) {
            _lastKnownPosition = progress;
          }
        }
      }
    });

    _controller!.setDataSource(
      safeUrl,
      headers: headers,
      liveStream: _isSports,
      startAt: widget.startPosition ?? Duration.zero,
    );
  }

  bool get _isSports =>
      !widget.isMovie && (widget.season == null || widget.episode == null);

  void _handleException(String message) async {
    if (_isHandlingException || _isRefreshing || _isDisposed) return;
    _isHandlingException = true;

    final errorStr = message.toLowerCase();

    // Specific HLS Live errors
    final isBehindLiveWindow =
        errorStr.contains('behindlivewindowexception') ||
        errorStr.contains('behind live window');
    final isPlaylistStuck =
        errorStr.contains('playliststuckexception') ||
        errorStr.contains('stuck');

    final isSourceError =
        isBehindLiveWindow ||
        isPlaylistStuck ||
        errorStr.contains('socket') ||
        errorStr.contains('ffurl') ||
        errorStr.contains('tcp') ||
        errorStr.contains('resolve') ||
        errorStr.contains('hostname') ||
        errorStr.contains('failed to open') ||
        errorStr.contains('could not open') ||
        errorStr.contains('unexpected end') ||
        errorStr.contains('stalled') ||
        errorStr.contains('timed out');

    final is403 = errorStr.contains('403') || errorStr.contains('forbidden');

    if (isBehindLiveWindow || isPlaylistStuck) {
      debugPrint(
        '[PlayerScreen] 🔄 Recovering from HLS specific error: $errorStr',
      );
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
        // If we are already on retry 2 or higher, we are using the proxy. 
        // If the proxy fails too, we should just fall back to the next provider immediately.
        if (_retryCount >= 2) {
          debugPrint('[PlayerScreen] ⚠️ Proxy fallback failed, moving to next provider...');
          _isHandlingException = false;
          await _fallbackToNextProvider();
          return;
        }

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
            _lastKnownPosition ?? _controller?.position ?? Duration.zero;

        String? newUrl;
        Map<String, String>? newHeaders;

        if (_isSports) {
          final refreshResult = await _refreshSportsStream();
          if (refreshResult != null && !_isDisposed) {
            newUrl = refreshResult['url'] as String?;
          }
        } else {
          final dynamic rawId = widget.item is Map
              ? (widget.item['media_id'] ?? widget.item['id'])
              : widget.item?.id;

          final int? mediaId = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '');

          if (mediaId == null) {
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
          // Decode HTML entities (critical for scraped sports links)
          newUrl = newUrl.replaceAll('&amp;', '&');
          debugPrint('[PlayerScreen] ✅ Re-fetched new URL: $newUrl');
          if (!mounted) return;

          await Future.delayed(const Duration(seconds: 2));
          if (_isDisposed || !mounted) return;

          // Determine if we should use the proxy for this retry
          // We use proxy on the 2nd and 3rd retry if it's a source error
          var finalHeaders = _getMergedHeaders(newUrl, widget.referrer, newHeaders);
          final finalUrl = (_retryCount >= 2) 
              ? _buildProxiedUrl(newUrl, finalHeaders)
              : newUrl;

          if (_retryCount >= 2) {
            debugPrint('[PlayerScreen] 🛡️ Using proxy fallback for retry $_retryCount');
            // When using proxy, we use a minimal set of headers for the client-to-proxy request,
            // but we MUST preserve or add Authorization to satisfy global API key middleware.
            finalHeaders = {
              'User-Agent': finalHeaders['User-Agent'] ?? '',
              'Accept': '*/*',
              'Authorization': 'Bearer $caffeineApiKey',
            };
          }

          // Re-initialize
          await _controller?.setDataSource(
            finalUrl,
            headers: finalHeaders,
            liveStream: _isSports,
            startAt: currentPosition,
          );

          if (!_isDisposed && mounted) {
            _isHandlingException = false;
            _safeSetState(() => _isRefreshing = false);
          }
        } else {
          _isHandlingException = false;
          _safeSetState(() => _isRefreshing = false);
          await _fallbackToNextProvider();
        }
      } catch (e) {
        _isHandlingException = false;
        _safeSetState(() => _isRefreshing = false);
      }
    } else {
      _isHandlingException = false;
      _safeSetState(() => _isRefreshing = false);
      if (isSourceError) {
        await _fallbackToNextProvider();
      } else {
        String friendlyMessage = message;
        if (errorStr.contains('failed to open')) {
          final provider = _getCleanProviderName();
          friendlyMessage = 'Failed to open stream from $provider. The source may be down or temporarily unavailable.';
        } else if (errorStr.contains('socket') || 
            errorStr.contains('connection') ||
            errorStr.contains('tcp') ||
            errorStr.contains('resolve')) {
          friendlyMessage = 'Server Connection Failed. The host could not be reached.';
        } else if (errorStr.contains('404')) {
          friendlyMessage = 'Content not found on this server.';
        } else if (errorStr.contains('403') || errorStr.contains('forbidden')) {
          friendlyMessage = 'Access denied by the provider.';
        }

        _safeSetState(() {
          _hasError = true;
          _errorMessage = friendlyMessage;
        });
      }
    }
  }

  String _getCleanProviderName() {
    if (widget.providerCode != null && widget.providerCode!.isNotEmpty) {
       // Capitalize first letter
       return widget.providerCode![0].toUpperCase() + widget.providerCode!.substring(1);
    }
    
    try {
      final uri = Uri.parse(widget.url);
      final host = uri.host.toLowerCase();
      if (host.contains('vidlink')) return 'VidLink';
      if (host.contains('vidsrc')) return 'Vidsrc';
      if (host.contains('vidfun')) return 'VidFun';
      if (host.contains('flixhq')) return 'FlixHQ';
      
      // If it's the proxy, try to decode the real URL
      if (host.contains('worker') || host.contains('proxy')) {
        final query = uri.queryParameters['url'];
        if (query != null) {
          final decoded = utf8.decode(base64.decode(query));
          final innerUri = Uri.parse(decoded);
          final innerHost = innerUri.host.toLowerCase();
          if (innerHost.contains('vidlink')) return 'VidLink';
          if (innerHost.contains('vidsrc')) return 'Vidsrc';
        }
      }
      
      return host.isNotEmpty ? host : 'the current provider';
    } catch (_) {
      return 'the current provider';
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
    if (_controller == null) return;
    final preferred = SettingsService().defaultAudioLanguage.toLowerCase();
    final tracks = _controller!.audioTracks;

    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      final title = track.title?.toLowerCase() ?? '';
      debugPrint('[PlayerScreen]   - Track: lang="$lang", title="$title"');

      final isMatch =
          lang == preferred ||
          lang.startsWith(preferred) ||
          title.startsWith(preferred) ||
          title.contains(preferred) ||
          (preferred == 'en' && title.contains('english'));

      if (isMatch) {
        debugPrint(
          '[PlayerScreen] ✅ Match found! Selecting track: $title ($lang)',
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
      
      // CRITICAL: Avoid loopback Referer. If we are hitting our own API, 
      // do NOT send the API host as the Referer. This triggers WAF/Nginx 
      // security rules (403 Forbidden).
      final apiHost = Uri.tryParse(_api.caffeineBaseUrl)?.host;
      if (apiHost != null && uri.host == apiHost) {
        return '';
      }

      // Most CDNs (vidlink, vidsrc) require the trailing slash on Referer
      return '${uri.scheme}://${uri.host}/';
    } catch (_) {
      return '';
    }
  }

  String _getOrigin(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        return url.replaceAll(RegExp(r'/$'), '');
      }
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
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
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
      if (value.length <= 8) return value; // Too short to be a URL
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
      // However, if we're hitting our own proxy, we skip this to avoid triggering security rules.
      final apiHost = Uri.tryParse(_api.caffeineBaseUrl)?.host;
      final targetHost = Uri.tryParse(url)?.host;
      if (!headers.containsKey('Origin') && targetHost != apiHost) {
        headers['Origin'] = 'https://vidlink.pro';
      }
    }

    // FINAL PRUNE: Ensure no loopback headers and remove browser-fingerprint headers
    // that the mobile app shouldn't be sending.
    final apiHost = Uri.tryParse(_api.caffeineBaseUrl)?.host;
    if (apiHost != null && Uri.tryParse(url)?.host == apiHost) {
      headers.removeWhere((k, v) {
        final key = k.toLowerCase();
        return key == 'referer' || key == 'origin' || key.startsWith('sec-');
      });
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

    // If this is a proxied URL, we need to inspect the TARGET domain for overrides
    String matchUrl = url;
    if (url.contains('/proxy/stream')) {
      try {
        final uri = Uri.parse(url);
        final encodedTarget = uri.queryParameters['url'];
        if (encodedTarget != null) {
          // Standard base64 or URL-safe base64
          final normalized =
              encodedTarget.replaceAll('-', '+').replaceAll('_', '/');
          final decoded = utf8.decode(base64.decode(
            normalized.padRight(
              normalized.length + (4 - normalized.length % 4) % 4,
              '=',
            ),
          ));
          matchUrl = decoded;
        }
      } catch (_) {}
    }

    if (!url.contains('headers=')) {
      if (matchUrl.contains('storm.vodvidl.site') ||
          matchUrl.contains('vidlink') ||
          matchUrl.contains('vidlvod') ||
          matchUrl.contains('vidl')) {
        headers['Referer'] = 'https://vidlink.pro/';
        headers['Origin'] = 'https://vidlink.pro';
      }


      if (matchUrl.contains('instreams.live')) {
        headers['Referer'] = 'https://instreams.click/';
        headers['Origin'] = 'https://instreams.click';
      }

      if (matchUrl.contains('strmd.st')) {
        headers['Referer'] = 'https://embed.st/';
        headers['Origin'] = 'https://embed.st';
      }

      if (matchUrl.contains('wfty.st')) {
        headers['Referer'] = 'https://sportsembed.su/';
        headers['Origin'] = 'https://sportsembed.su';
      }
    }

    // Log final resolved headers for debugging (only if not already proxied to avoid spam)
    if (!url.contains('/proxy/stream')) {
      debugPrint(
        '[PlayerScreen] 🔑 Final headers for ${Uri.tryParse(url)?.host}: '
        'Referer=${headers['Referer']}, Origin=${headers['Origin']}',
      );
    }

    return headers;
  }

  String _buildProxiedUrl(String targetUrl, Map<String, String> headers) {
    if (targetUrl.contains('/proxy/stream') || targetUrl.contains('workers.dev')) {
      return targetUrl;
    }
    try {
      final baseUrl = _api.caffeineBaseUrl;
      final apiKey = caffeineApiKey;
      final encodedUrl = base64Url.encode(utf8.encode(targetUrl));
      final encodedHeaders = base64Url.encode(utf8.encode(jsonEncode(headers)));

      String extension = "";
      final pureUrl = targetUrl.split("?")[0];
      
      // Force .m3u8 for known HLS providers that don't always use the extension
      final isHlsProvider = targetUrl.contains('vixsrc') || 
                           targetUrl.contains('vidlink') || 
                           targetUrl.contains('vidsrc');

      if (pureUrl.endsWith(".m3u8") || (isHlsProvider && !pureUrl.endsWith(".ts") && !pureUrl.endsWith(".mp4"))) {
        extension = "/video.m3u8";
      } else if (pureUrl.endsWith(".ts")) {
        extension = "/segment.ts";
      } else if (pureUrl.endsWith(".mp4")) {
        extension = "/video.mp4";
      }

      // Add the key parameter for authorization if we have an API key
      final authParam = apiKey.isNotEmpty ? "&key=$apiKey" : "";
      return "$baseUrl/proxy/stream$extension?url=$encodedUrl&headers=$encodedHeaders$authParam";
    } catch (e) {
      debugPrint('[PlayerScreen] ❌ Failed to build proxied URL: $e');
      return targetUrl;
    }
  }

  Future<void> _fallbackToNextProvider() async {
    _trackSessionEnd();
    await _saveCurrentProgress();
    if (_isDisposed || !mounted) return;

    if (_isSports) {
       // Sports handles its own fallback as it doesn't use VideoLoaderScreen
       _fallbackSportsToNextProvider();
       return;
    }

    debugPrint('[PlayerScreen] 🔄 Signaling fallback to next provider...');
    Navigator.of(context).pop(true); // Return true to signal fallback needed
  }

  void _fallbackSportsToNextProvider() {
    final currentPos = _controller?.position ?? _lastKnownPosition;
    
    if (widget.allProviders == null || widget.allProviders!.isEmpty) {
      debugPrint('[PlayerScreen] ❌ No provider list for auto-fallback');
      _showSettings(); 
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
        '[PlayerScreen] 🔄 Auto-falling back to next sports mirror: $nextProviderCode',
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              url: nextProviderCode,
              title: widget.title,
              item: widget.item,
              isMovie: false,
              referrer: nextProvider['referrer'],
              allProviders: widget.allProviders,
              startPosition: currentPos,
              providerCode: nextProviderCode,
            ),
          ),
        );
      }
    } else {
      debugPrint('[PlayerScreen] ❌ All sports mirrors exhausted');
      _showSettings(); 
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

          final currentPos =
              _controller?.position ??
              _lastKnownPosition;

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
                if (!context.mounted) return;
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
            // For sports, we should have already returned above.
            // If we reach here, it's a movie or TV show.
            if (!context.mounted) return;
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
      movie: (widget.isMovie && widget.item is core.MovieDetail)
          ? widget.item as core.MovieDetail
          : null,
      tvShow: (!widget.isMovie && widget.item is core.TvShowDetail)
          ? widget.item as core.TvShowDetail
          : null,
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
        debugPrint(
          '[PlayerScreen] ✅ Found ${searchResults.length} new subtitles',
        );

        final langName = supportedLanguages
            .firstWhere(
              (l) => l.languageCode == langCode,
              orElse: () => SubLanguages(
                languageName: '',
                languageCode: '',
                englishName: 'Unknown',
              ),
            )
            .englishName;

        bool activated = false;
        for (var data in searchResults) {
          final fileId = data.attr?.files?.first.fileId;
          if (fileId != null) {
            final downloadUrl = await _subtitleService.downloadSubtitle(
              fileId,
              SettingsService().opensubtitlesKey,
            );
            if (downloadUrl != null && !_isDisposed && mounted) {
              final trackName = '$langName (OpenSubtitles)';
              final newTrack = SubtitleTrack.uri(
                downloadUrl,
                title: trackName,
              );

              debugPrint(
                '[PlayerScreen] 🔤 Activating downloaded subtitle track: $trackName ($downloadUrl)',
              );

              // Directly set subtitle track on active controller without stream reload
              _controller?.setSubtitleTrack(newTrack);
              activated = true;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Subtitles loaded: $langName'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              break;
            }
          }
        }

        if (!activated) {
          debugPrint('[PlayerScreen] ❌ Failed to download subtitle file');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not download subtitles'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        debugPrint(
          '[PlayerScreen] ℹ️ No subtitles found for language: $langCode',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No subtitles found for $langCode'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
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

    _retryCount++;
    if (_retryCount >= 4) {
      debugPrint(
        '[PlayerScreen] 🛑 Too many resets/stalls, falling back to next provider',
      );
      await _fallbackToNextProvider();
      return;
    }

    await _saveCurrentProgress();
    final ctrlPos = _controller?.position;
    final currentPosition = (ctrlPos != null && ctrlPos > const Duration(seconds: 5))
        ? ctrlPos
        : (_lastKnownPosition != null && _lastKnownPosition! > const Duration(seconds: 5)
            ? _lastKnownPosition
            : (widget.startPosition ?? Duration.zero));

    debugPrint(
      '[PlayerScreen] 🔄 Forcing player reset (media_kit)... '
      '(saving position: ${currentPosition?.inSeconds}s)',
    );
    try {
      // 1. Decode HTML entities (critical for scraped sports links)
      var safeUrl = widget.url.replaceAll('&amp;', '&');
      var headers = _getMergedHeaders(safeUrl, widget.referrer, widget.headers);
      
      try {
        final uri = Uri.parse(safeUrl);
        if (uri.host == 'videostr.net' || uri.host.endsWith('.videostr.net')) {
          safeUrl = uri.replace(host: 'vidlink.pro').toString();
          headers = _getMergedHeaders(safeUrl, widget.referrer, widget.headers);
        }

        if (uri.host.contains('instreams.live') || uri.host.contains('wfty.st')) {
          safeUrl = _buildProxiedUrl(safeUrl, headers);
          headers = {
            'User-Agent': headers['User-Agent'] ?? '',
            'Accept': '*/*',
          };
        }
      } catch (e, stack) {
        debugPrint('[PlayerScreen] ❌ Reset rewrite error: $e\n$stack');
      }

      await _controller?.setDataSource(
        safeUrl,
        headers: headers,
        liveStream: _isSports,
        startAt: currentPosition ?? widget.startPosition ?? Duration.zero,
      );

      if (!_isDisposed && mounted) {
        _controller?.play();
        debugPrint('[PlayerScreen] ✅ Forced reset complete');
      }
    } catch (e) {
      debugPrint('[PlayerScreen] ❌ Error during forced reset: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('[PlayerScreen] 🛑 Disposing PlayerScreen...');
    _isDisposed = true;
    _trackSessionEnd();
    _saveTimer?.cancel();
    _initWatchdogTimer?.cancel();
    _saveCurrentProgress(); // Best effort save
    _visibilitySubscription?.cancel();
    WakelockManager.disable();
    OutageService.instance.resume();

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
            if (mounted && context.mounted) Navigator.of(context).pop();
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
          if (!_controlsVisible && !_isDisposed) _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaFastForward(key)) {
          debugPrint('[PlayerScreen] ⏩ Media Fast Forward key');
          final pos = _controller?.position;
          if (pos != null) {
            _controller?.seekTo(pos + const Duration(seconds: 10));
          }
          if (!_controlsVisible && !_isDisposed) _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaRewind(key)) {
          debugPrint('[PlayerScreen] ⏪ Media Rewind key');
          final pos = _controller?.position;
          if (pos != null) {
            final target = pos - const Duration(seconds: 10);
            _controller?.seekTo(
              target < Duration.zero ? Duration.zero : target,
            );
          }
          if (!_controlsVisible && !_isDisposed) _setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaStop(key)) {
          debugPrint('[PlayerScreen] ⏹️ Media Stop key');
          _saveCurrentProgress().then((_) {
            if (mounted && context.mounted) Navigator.of(context).pop();
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
          if (mounted && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (_controller != null)
                mkv.Video(controller: _controller!.videoController),

              // TV Controls overlay
              if (_controller != null && !_hasError)
                TvPlayerControls(
                  controller: _controller!,
                  onVisibilityChanged: (visible) {
                    _safeSetState(() {
                      _controlsVisible = visible;
                    });
                  },
                  onShowSettings: _showSettings,
                  nextEpisode: widget.nextEpisode,
                  quality: widget.quality,
                  onNextEpisode: () async {
                    await _saveCurrentProgress();
                    if (context.mounted) {
                      Navigator.of(context).pop({'action': 'next'});
                    }
                  },
                ),

              // Loading overlay: stays in the tree to allow for the fade-out
              // animation when _hasInitialized becomes true.
              _buildLoadingOverlay(),

              // Premium Error Overlay
              if (_hasError) _buildErrorOverlay(),
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
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white70,
                            ),
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


  void _setControlsVisibility(bool visible) {
    if (_isDisposed || !mounted || _controller == null) return;
    try {
      _controller?.toggleControlsVisibility(visible);
    } catch (e) {
      debugPrint('[PlayerScreen] ⚠️ Failed to set controls visibility: $e');
    }
  }

  Widget _buildErrorOverlay() {
    final imageUrl = _posterUrl;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background blurred poster
            if (imageUrl != null)
              Opacity(
                opacity: 0.3,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            
            // Glass effect
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            Center(
              child: FocusScope(
                autofocus: true,
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC1D24).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFEC1D24).withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFEC1D24),
                            size: 80,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'PLAYBACK ERROR',
                          style: TextStyle(
                            color: const Color(0xFFEC1D24).withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage ?? 'An unexpected error occurred while playing this content.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Please try again or select a different server from the settings menu.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildErrorButton(
                              label: 'Try Again',
                              icon: Icons.refresh_rounded,
                              isPrimary: true,
                              onPressed: () {
                                _safeSetState(() {
                                  _hasError = false;
                                  _retryCount = 0;
                                });
                                _setupController();
                              },
                            ),
                            const SizedBox(width: 20),
                            _buildErrorButton(
                              label: 'Change Server',
                              icon: Icons.dns_rounded,
                              onPressed: () {
                                _safeSetState(() {
                                  _hasError = false;
                                });
                                _showSettings();
                              },
                            ),
                            const SizedBox(width: 20),
                            _buildErrorButton(
                              label: 'Go Back',
                              icon: Icons.arrow_back_rounded,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return Focus(
      autofocus: isPrimary,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white
                    : (isPrimary
                        ? const Color(0xFFEC1D24).withValues(alpha: 0.2)
                        : Colors.white10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused
                      ? Colors.white
                      : (isPrimary ? const Color(0xFFEC1D24) : Colors.white24),
                  width: 2,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isFocused
                        ? Colors.black
                        : (isPrimary ? const Color(0xFFEC1D24) : Colors.white),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: isFocused ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
