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
import 'dart:convert';
import 'package:caffeine_tv/services/subtitle_service.dart';
import 'package:caffeine_tv/widgets/language_picker_dialog.dart';
import 'package:caffeine_tv/models/sub_languages.dart';

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
    this.imdbId,
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
  final String? imdbId;

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
  bool _controlsVisible = false;
  StreamSubscription? _visibilitySubscription;
  int _retryCount = 0;
  final ApiService _api = ApiService();
  bool _isRefreshing = false;
  bool _isDisposed = false;
  bool _isHandlingException = false;
  Duration? _lastKnownPosition;

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

    _visibilitySubscription = _controller?.controlsVisibilityStream.listen((
      visible,
    ) {
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
    if (_controller == null || _controller!.videoPlayerController == null)
      return;

    final duration =
        _controller!.videoPlayerController!.value.duration ?? Duration.zero;
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
        widget.url,
        videoFormat:
            widget.url.contains('m3u8') ||
                widget.url.contains('playlist') ||
                widget.url.contains('proxy/stream')
            ? BetterPlayerVideoFormat.hls
            : null,
        useAsmsTracks: true,
        useAsmsAudioTracks: true,
        useAsmsSubtitles: true,
        subtitles: widget.externalSubtitles,
        preferredAudioLanguage: SettingsService().defaultAudioLanguage,
        headers: _getMergedHeaders(widget.url, widget.referrer, widget.headers),
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 30000,
          maxBufferMs: 60000,
          bufferForPlaybackMs: 2500,
          bufferForPlaybackAfterRebufferMs: 5000,
        ),
      ),
    );
    debugPrint('[PlayerScreen] 📺 Playing: ${widget.url}');
    debugPrint(
      '[PlayerScreen] 🔗 Referrer: ${widget.referrer ?? _getReferer(widget.url)}',
    );

    _controller!.addEventsListener((event) async {
      if (_isDisposed) return;
      if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
        debugPrint(
          '[PlayerScreen] 🎉 Video finished, saving final progress (100%) and closing',
        );
        await _saveCurrentProgress(isFinished: true);
        if (mounted && !_isDisposed) Navigator.of(context).pop();
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.initialized) {
        // Try multiple times as tracks might load late in HLS manifest
        _selectPreferredAudioTrack();
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _selectPreferredAudioTrack(),
        );
        Future.delayed(
          const Duration(milliseconds: 1500),
          () => _selectPreferredAudioTrack(),
        );
        Future.delayed(
          const Duration(milliseconds: 3000),
          () => _selectPreferredAudioTrack(),
        );
        Future.delayed(
          const Duration(milliseconds: 5000),
          () => _selectPreferredAudioTrack(),
        );
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.exception) {
        if (!_isDisposed) _handlePlayerException(event);
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.progress) {
        if (!_isDisposed) {
          _lastKnownPosition = event.parameters?['progress'] as Duration?;
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
    final isSourceError =
        errorStr.contains('source error') ||
        errorStr.contains('httpdatasource') ||
        errorStr.contains('sockettimeout') ||
        errorStr.contains('unexpected end of stream');
    // 403 = IP-locked / auth error — retrying the same URL is pointless, skip straight to fallback
    final is403 =
        errorStr.contains('response code: 403') ||
        errorStr.contains('invalidresponsecodeexception') &&
            errorStr.contains('403');

    if (is403) {
      debugPrint(
        '[PlayerScreen] 🚫 403 Forbidden — IP-locked URL, skipping retries, falling back...',
      );
      _isHandlingException = false;
      _safeSetState(() => _isRefreshing = false);
      _fallbackToNextProvider();
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
          if (refreshResult != null) {
            newUrl = refreshResult['url'];
            newReferrer = refreshResult['referrer'];
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
              bufferingConfiguration: const BetterPlayerBufferingConfiguration(
                minBufferMs: 30000,
                maxBufferMs: 60000,
                bufferForPlaybackMs: 2500,
                bufferForPlaybackAfterRebufferMs: 5000,
              ),
            ),
          );

          if (!_isDisposed && mounted) {
            _controller?.play();
            _controller?.seekTo(currentPosition);
            _safeSetState(() => _isRefreshing = false);
          }
        } else {
          debugPrint('[PlayerScreen] ❌ Re-fetch failed or returned no links');
          _isHandlingException = false;
          _safeSetState(() {
            _isRefreshing = false;
            if (widget.isMovie || widget.episode != null) {
              // Automatically try another provider if re-fetch failed
              _fallbackToNextProvider();
            } else {
              _hasError = true;
              _errorMessage =
                  'Failed to refresh stream. Please try again later.';
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
        if (isSourceError && (widget.isMovie || widget.episode != null)) {
          // Source kept failing after retries — try next provider automatically
          _fallbackToNextProvider();
        } else {
          _hasError = true;
          _errorMessage = exception?.toString() ?? 'Playback error';
        }
      });
    }
  }

  Future<Map<String, String?>?> _refreshSportsStream() async {
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

    // Merge extra headers first
    if (extra != null) {
      for (final entry in extra.entries) {
        headers[normalizeKey(entry.key)] = entry.value;
      }
    }

    // Add default Referer and Origin if not already set by extra
    final effectiveReferrer = referrer ?? _getReferer(url);
    if (effectiveReferrer.isNotEmpty) {
      if (!headers.containsKey('Referer')) {
        headers['Referer'] = effectiveReferrer;
      }
      if (!headers.containsKey('Origin')) {
        headers['Origin'] = _getOrigin(effectiveReferrer);
      }
    }

    // Add Referrer (double R) as a duplicate of Referer for extra compatibility
    // Some streams specifically check for this variation.
    if (headers.containsKey('Referer')) {
      headers['Referrer'] = headers['Referer']!;
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

    return headers;
  }

  void _fallbackToNextProvider() {
    if (_isDisposed || !mounted) return;

    final currentPos = _controller?.videoPlayerController?.value.position;

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

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => _buildVideoLoader(nextProviderCode, currentPos),
        ),
      );
    } else {
      debugPrint('[PlayerScreen] ❌ All providers exhausted for auto-fallback');
      _showSettings(); // Show picker as last resort
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
        providerLabel: _isSports ? 'Select Mirror' : 'Server (Provider)',
        onSearchMore: _searchMoreSubtitles,
        onChangeProvider: (newProviderCode) {
          // Close settings dialog
          Navigator.of(context).pop();
          final currentPos = _controller?.videoPlayerController?.value.position;
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

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  _buildVideoLoader(newProviderCode, currentPos),
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

  Future<void> _searchMoreSubtitles(String langCode) async {
    if (widget.imdbId == null) {
      debugPrint('[PlayerScreen] ❌ IMDB ID is null, cannot search subtitles');
      return;
    }

    _safeSetState(() {
      _isRefreshing = true;
    });

    try {
      final searchResults = await _subtitleService.searchSubtitles(
        imdbId: widget.imdbId!,
        languageCode: langCode,
        apiKey: SettingsService().opensubtitlesKey,
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
              bufferForPlaybackMs: 2500,
              bufferForPlaybackAfterRebufferMs: 5000,
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
            _controller?.setControlsVisibility(true);
          return KeyEventResult.handled;
        }

        if (TvKeys.isMediaFastForward(key)) {
          debugPrint('[PlayerScreen] ⏩ Media Fast Forward key');
          final pos = _controller?.videoPlayerController?.value.position;
          if (pos != null) {
            _controller?.seekTo(pos + const Duration(seconds: 10));
          }
          if (!_controlsVisible && !_isDisposed)
            _controller?.setControlsVisibility(true);
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
            _controller?.setControlsVisibility(true);
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
            if (!_isDisposed) _controller?.setControlsVisibility(true);
          } else {
            // Safety: keep-alive the visibility timer.
            if (!_isDisposed) _controller?.setControlsVisibility(true);
          }
          return KeyEventResult.ignored;
        }

        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _saveCurrentProgress();
          if (mounted) Navigator.of(context).pop();
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
              : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : BetterPlayer(controller: _controller!),
        ),
      ),
    );
  }
}
