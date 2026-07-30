import 'package:caffeine_core/caffeine_core.dart' as core;
import 'dart:async';
import 'dart:convert';
import 'package:reelriot_tv/services/outage_service.dart';
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/models/provider_load_state.dart';
import 'package:reelriot_tv/screens/player_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/services/subtitle_service.dart';
import 'package:reelriot_tv/models/sub_languages.dart';
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:reelriot_tv/widgets/provider_loading_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/utils/video_utils.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelriot_tv/utils/wakelock_manager.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';

class VideoLoaderScreen extends StatefulWidget {
  final core.MovieDetail? movie;
  final core.TvShowDetail? tvShow;
  final int? season;
  final int? episode;
  final int? episodeId;
  final String? episodeName;
  final Duration? startPosition;
  final String? preferredProvider;

  const VideoLoaderScreen({
    this.movie,
    this.tvShow,
    this.season,
    this.episode,
    this.episodeId,
    this.episodeName,
    this.startPosition,
    this.preferredProvider,
    super.key,
  });

  @override
  State<VideoLoaderScreen> createState() => _VideoLoaderScreenState();
}

class _VideoLoaderScreenState extends State<VideoLoaderScreen> {
  final ApiService _api = ApiService();
  final WatchHistoryService _historyService = WatchHistoryService();
  final SubtitleService _subtitleService = SubtitleService();
  final SettingsService _settings = SettingsService();

  final List<Map<String, String>> _providers = [
    {'code': 'vidlink', 'name': 'VidLink'},
    {'code': 'vidsrcsu', 'name': 'VidSrc.su'},
    {'code': 'vidsrcme', 'name': 'VidSrc.me'},
    {'code': 'nxsha', 'name': 'Nxsha'},
    {'code': 'vidfun', 'name': 'VidFun'},
    {'code': 'flixhq', 'name': 'FlixHQ'},
  ];

  late List<ProviderLoadState> _providerStates;
  int _currentProviderIndex = 0;
  bool _isDone = false;

  // Track current episode state for "Next Episode" looping
  int? _currentSeason;
  int? _currentEpisode;
  int? _currentEpisodeId;
  String? _currentEpisodeName;
  Duration? _currentStartPosition;

  @override
  void initState() {
    super.initState();
    WakelockManager.enable();
    OutageService.instance.pause();

    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _currentEpisodeId = widget.episodeId;
    _currentEpisodeName = widget.episodeName;
    _currentStartPosition = widget.startPosition;

    // Prioritize preferred provider if specified
    if (widget.preferredProvider != null) {
      final prefIndex = _providers.indexWhere(
        (p) => p['code'] == widget.preferredProvider,
      );
      if (prefIndex != -1) {
        final pref = _providers.removeAt(prefIndex);
        _providers.insert(0, pref);
      }
    }

    _providerStates = _providers
        .map(
          (p) => ProviderLoadState(
            codeName: p['code']!,
            fullName: p['name']!,
            status: ProviderStatus.pending,
          ),
        )
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadVideo();
      }
    });
  }

  Future<Map<String, dynamic>?> _fetchNextEpisode() async {
    if (widget.tvShow == null || _currentSeason == null || _currentEpisode == null) {
      return null;
    }

    try {
      final seasonDetail = await _api.fetchSeasonDetail(
        widget.tvShow!.id,
        _currentSeason!,
      );

      // Check if there is another episode in this season
      for (var ep in seasonDetail.episodes) {
        if (ep.episodeNumber == _currentEpisode! + 1) {
          return {
            'season': _currentSeason,
            'episode': ep.episodeNumber,
            'episodeId': ep.id,
            'episodeName': ep.name,
          };
        }
      }

      // Check if there is a next season
      final tvDetail = await _api.fetchTvDetail(widget.tvShow!.id);
      if (_currentSeason! < (tvDetail.numberOfSeasons ?? 0)) {
        final nextSeasonDetail = await _api.fetchSeasonDetail(
          widget.tvShow!.id,
          _currentSeason! + 1,
        );
        if (nextSeasonDetail.episodes.isNotEmpty) {
          final firstEp = nextSeasonDetail.episodes.first;
          return {
            'season': _currentSeason! + 1,
            'episode': firstEp.episodeNumber,
            'episodeId': firstEp.id,
            'episodeName': firstEp.name,
          };
        }
      }
    } catch (e) {
      debugPrint('[VideoLoader] ⚠️ Error fetching next episode: $e');
    }
    return null;
  }

  Future<String> _getQualityBadge() async {
    final mediaId = widget.movie?.id ?? widget.tvShow?.id;
    if (mediaId == null) return 'HD';

    return await QualityUtils.getQualityBadgeAsync(
      mediaId: mediaId,
      releaseDate: widget.movie?.releaseDate,
      isMovie: widget.movie != null,
    ) ?? 'HD';
  }

  void _loadVideo() async {
    final mediaId = widget.movie?.id ?? widget.tvShow?.id;
    final mediaName = widget.movie?.title ?? widget.tvShow?.name;
    debugPrint('[VideoLoader] 🎬 Loading media: $mediaName (ID: $mediaId)');
    if (widget.tvShow != null) {
      debugPrint(
        '[VideoLoader] 📺 TV Show: S$_currentSeason E$_currentEpisode',
      );
      if (_currentSeason == null || _currentEpisode == null) {
        debugPrint(
          '[VideoLoader] ❌ Cannot load TV stream: season or episode missing',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not determine which episode to play'),
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }
    }

    // Reset provider states for a fresh load (used when transitioning to next episode)
    setState(() {
      _isDone = false;
      _currentProviderIndex = 0;
      for (var state in _providerStates) {
        state.status = ProviderStatus.pending;
      }
    });

    // Pre-fetch "Up Next" metadata and Quality Badge
    final nextEpDataFuture = _fetchNextEpisode();
    final qualityBadgeFuture = _getQualityBadge();

    final nextEpData = await nextEpDataFuture;
    final qualityBadge = await qualityBadgeFuture;

    // 2. Fetch all streams concurrently but stream the results
    final StreamController<int> resultStream = StreamController<int>();
    int completedCount = 0;
    final List<core.ProviderStreamResponse?> responses = List.filled(_providers.length, null);
    
    for (int i = 0; i < _providers.length; i++) {
      final providerCode = _providers[i]['code']!;
      final providerName = _providers[i]['name']!;
      
      setState(() {
        _providerStates[i].status = ProviderStatus.loading;
      });

      Future<core.ProviderStreamResponse?> fetchFuture;
      if (widget.movie != null) {
        fetchFuture = _api.fetchMovieStream(widget.movie!.id, provider: providerCode)
            .then((res) => res as core.ProviderStreamResponse?);
      } else {
        fetchFuture = _api.fetchTvStream(widget.tvShow!.id, _currentSeason!, _currentEpisode!, provider: providerCode)
            .then((res) => res as core.ProviderStreamResponse?);
      }

      fetchFuture.then((response) {
        completedCount++;
        
        if (response != null && response.success && response.links != null && response.links!.isNotEmpty) {
          // Defensive filter: Only keep playable HLS (.m3u8), MP4 or proxied media stream URLs.
          // Reject raw HTML iframe embed URLs (e.g. /embed/, web.nxsha.app) even if wrapped in a proxy URL.
          response.links!.retainWhere((link) {
            final isPlayable = _isPlayableMediaUrl(link.url, link.isM3U8);
            if (!isPlayable) {
              debugPrint('[VideoLoader] ⚠️ Filtering out unplayable/embed URL: ${link.url}');
            }
            return isPlayable;
          });
          
          if (response.links!.isNotEmpty) {
            responses[i] = response;
            if (!resultStream.isClosed) {
               resultStream.add(i);
            }
            return;
          } else {
            debugPrint('[VideoLoader] ⚠️ Provider $providerName returned invalid streams.');
            if (mounted) {
              setState(() {
                _providerStates[i].status = ProviderStatus.failed;
              });
            }
          }
        } else {
          debugPrint('[VideoLoader] ❌ Provider $providerName returned no links or success=false');
          if (mounted) {
            setState(() {
              _providerStates[i].status = ProviderStatus.failed;
            });
          }
        }

        if (completedCount == _providers.length && !resultStream.isClosed) {
          resultStream.add(-1);
        }
      }).catchError((e) {
        debugPrint('[VideoLoader] ⚠️ Error with provider $providerName: $e');
        if (mounted) {
          setState(() {
            _providerStates[i].status = ProviderStatus.failed;
          });
        }
        completedCount++;
        if (completedCount == _providers.length && !resultStream.isClosed) {
          resultStream.add(-1);
        }
      });
    }

    // Start a timer to cycle the loading text to mimic web app
    Timer? cycleTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted) {
        setState(() {
          _currentProviderIndex = (_currentProviderIndex + 1) % _providers.length;
        });
      } else {
        timer.cancel();
      }
    });

    // 1. Determine start position (cached for retries)
    Duration? startPos;
    if (_currentStartPosition != null) {
      startPos = _currentStartPosition;
    } else {
      startPos = await _historyService.getSavedProgress(
        mediaId!,
        widget.movie != null,
        season: _currentSeason,
        episode: _currentEpisode,
      );
      // Cache it so subsequent provider retries use the same position
      _currentStartPosition = startPos;
    }

    await for (final winningIndex in resultStream.stream) {
      if (!mounted) break;
      if (winningIndex == -1) {
         break; // All failed
      }

      final providerCode = _providers[winningIndex]['code']!;
      final providerName = _providers[winningIndex]['name']!;
      final response = responses[winningIndex]!;

      setState(() {
        _currentProviderIndex = winningIndex;
      });

      debugPrint('[VideoLoader] ✅ Found ${response.links!.length} stream(s) from $providerName');

      if (!mounted) return;

      // 1. Collect all potential subtitle links
      List<core.SubtitleLink> allSubtitleLinks = [];

      debugPrint(
        '[VideoLoader] ℹ️ Subtitle Settings: useExternal=${_settings.useExternalSubtitles}, hasKey=${_settings.opensubtitlesKey.isNotEmpty}',
      );

      // External Subtitles (Prioritized)
      if (_settings.useExternalSubtitles &&
          _settings.opensubtitlesKey.isNotEmpty) {
        debugPrint(
          '[VideoLoader] 🔍 External subtitles enabled. Checking Open Subtitles...',
        );
        try {
          final int tmdbId = widget.movie?.id ?? widget.tvShow!.id;
          // Search for English, Spanish, and the user's default language
          final validLangs = {
            'en',
            'es',
            _settings.language,
          }.where((l) => l.isNotEmpty).toSet();
          final searchLangs = validLangs.join(',');

          final extSubs = await _subtitleService.searchSubtitles(
            tmdbId: tmdbId,
            languageCode: searchLangs,
            apiKey: _settings.opensubtitlesKey,
            seasonNumber: _currentSeason,
            episodeNumber: _currentEpisode,
          );

          if (extSubs.isNotEmpty) {
            debugPrint(
              '[VideoLoader] ✅ Found ${extSubs.length} Open Subtitles. Adding top tracks...',
            );

            // Track added languages to ensure diversity (one best per lang)
            final addedLangs = <String>{};
            int addedCount = 0;

            for (var sub in extSubs) {
              if (addedCount >= 4) break;

              final lang = sub.attr?.language ?? '';
              final fileId = sub.attr?.files?.first.fileId;

              if (fileId != null && !addedLangs.contains(lang)) {
                final downloadUrl = await _subtitleService.downloadSubtitle(
                  fileId,
                  _settings.opensubtitlesKey,
                );

                if (downloadUrl != null) {
                  addedLangs.add(lang);
                  addedCount++;
                  allSubtitleLinks.add(
                    core.SubtitleLink(
                      file: downloadUrl,
                      label:
                          '${sub.attr?.languageName ?? lang} (OpenSubtitles)',
                    ),
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint(
            '[VideoLoader] ⚠️ External subtitle search failed: $e',
          );
        }
      }

      // Internal subtitles from provider (Fallback/Secondary)
      if (response.links!.first.subtitles.isNotEmpty) {
        debugPrint(
          '[VideoLoader] 📝 Found ${response.links!.first.subtitles.length} internal subtitles',
        );
        allSubtitleLinks.addAll(response.links!.first.subtitles);
      }

      // 2. Parse and process all collected subtitles
      final langIndex = supportedLanguages.indexWhere(
        (l) => l.languageCode == _settings.language,
      );
      final defaultLanguage = langIndex != -1
          ? supportedLanguages[langIndex].englishName
          : 'English';

      final List<CaffeinePlayerSubtitlesSource> subs = await VideoUtils.parseSubtitles(
        subtitles: allSubtitleLinks,
        defaultLanguage: defaultLanguage,
        fetchAllLanguages: true, // TV app generally wants more choice
        getSubtitleContent: _subtitleService.getSubtitleContent,
      );

      debugPrint(
        '[VideoLoader] 🏁 Total processed subtitles: ${subs.length}',
      );

      if (!mounted) return;
      
      // Stop the cycling timer as soon as we succeed!
      cycleTimer.cancel();
      
      setState(() {
        _providerStates[winningIndex].status = ProviderStatus.success;
        _isDone = true;
      });

      debugPrint(
        '[VideoLoader] 🚀 Launching PlayerScreen with URL: ${response.links!.first.url}',
      );
      
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            url: response.links!.first.url,
            title: widget.movie?.title ?? widget.tvShow?.name ?? 'Video',
            item: widget.movie ?? widget.tvShow,
            isMovie: widget.movie != null,
            season: _currentSeason,
            episode: _currentEpisode,
            episodeId: _currentEpisodeId,
            episodeName: _currentEpisodeName,
            nextEpisode: nextEpData,
            startPosition: startPos,
            providerCode: providerCode,
            allProviders: _providers,
            quality: qualityBadge,
            headers: response.links!.first.headers,
            externalSubtitles: subs,
          ),
        ),
      );

      if (result == true) {
        debugPrint('[VideoLoader] 🔄 Player signaled fallback. Retrying...');
        if (mounted) {
          setState(() {
            _providerStates[winningIndex].status = ProviderStatus.failed;
            _isDone = false;
          });
        }
        continue; 
      } else if (result is Map && result['action'] == 'next') {
        debugPrint('[VideoLoader] ⏭️ Player signaled Next Episode.');
        if (nextEpData != null && mounted) {
          setState(() {
            _currentSeason = nextEpData['season'];
            _currentEpisode = nextEpData['episode'];
            _currentEpisodeId = nextEpData['episodeId'];
            _currentEpisodeName = nextEpData['episodeName'];
            _currentStartPosition = null;
          });
          // Loop back to start loading the next one
          resultStream.close();
          _loadVideo();
          return;
        }
      }

      // User manually popped or finished video, so we also close the loader
      debugPrint('[VideoLoader] 🔚 Player session ended. Closing loader.');
      resultStream.close();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    cycleTimer.cancel();

    if (mounted && !_isDone) {
      debugPrint(
        '[VideoLoader] 🚫 All providers failed to return a stream for $mediaName',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stream available from any provider')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    WakelockManager.disable();
    OutageService.instance.resume();
    super.dispose();
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => _scale(context, v);
    final backdropPath =
        widget.movie?.backdropPath ?? widget.tvShow?.backdropPath;
    final title = widget.movie?.title ?? widget.tvShow?.name ?? 'Loading...';

    final currentProvider = _providerStates[_currentProviderIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fullscreen Backdrop (Crisp, not blurred)
          if (backdropPath != null)
            CachedNetworkImage(
              imageUrl: '$tmdbImageBaseUrl/original$backdropPath',
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
              placeholder: (_, _) => Container(color: Colors.black),
            ),

          // 2. Premium Linear Gradient (Matches PlayerScreen)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // 3. Content - Anchored to bottom-left
          Positioned(
            left: 56,
            right: 56,
            bottom: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimalist Provider Status
                _buildStatusIndicator(currentProvider),

                SizedBox(height: s(24)),

                // Title
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s(56),
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // Episode / Year Info
                if (widget.tvShow != null ||
                    widget.movie?.releaseDate != null) ...[
                  SizedBox(height: s(8)),
                  Text(
                    widget.tvShow != null
                        ? 'Season ${widget.season}  •  Episode ${widget.episode}${widget.episodeName != null ? "  •  ${widget.episodeName}" : ""}'
                        : (widget.movie?.releaseDate?.split('-').first ?? ''),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: s(24),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(ProviderLoadState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                state.status == ProviderStatus.failed
                    ? Colors.redAccent
                    : Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            state.status == ProviderStatus.loading
                ? 'Searching ${state.fullName}…'
                : 'Connecting to ${state.fullName}…',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  bool _isPlayableMediaUrl(String rawUrl, bool? isM3U8) {
    final lowerUrl = rawUrl.toLowerCase();
    if (!lowerUrl.startsWith('http') && !lowerUrl.startsWith('/')) return false;

    // Extract real target URL if proxied via /proxy/stream?url=...
    String targetUrl = lowerUrl;
    if (lowerUrl.contains('url=')) {
      try {
        final uri = Uri.parse(rawUrl);
        final encodedTarget = uri.queryParameters['url'];
        if (encodedTarget != null && encodedTarget.isNotEmpty) {
          try {
            final normalizedB64 = encodedTarget.replaceAll('-', '+').replaceAll('_', '/');
            final padded = normalizedB64.padRight((normalizedB64.length + 3) & ~3, '=');
            targetUrl = utf8.decode(base64.decode(padded)).toLowerCase();
          } catch (_) {
            targetUrl = Uri.decodeComponent(encodedTarget).toLowerCase();
          }
        }
      } catch (_) {}
    }

    // Check if the target is a raw HTML embed page (e.g. /embed/, web.nxsha.app, vidsrcme.ru)
    final isEmbed = targetUrl.contains('/embed/') ||
                    targetUrl.contains('embed.html') ||
                    targetUrl.contains('web.nxsha.app') ||
                    targetUrl.contains('vidsrcme.ru') ||
                    targetUrl.contains('wfs.lol/embed');

    // Check if target is a valid direct media stream (.m3u8, .mp4, playlist)
    final isDirectMedia = targetUrl.contains('.m3u8') ||
                          targetUrl.contains('.mp4') ||
                          targetUrl.contains('/proxy/stream/video.m3u8') ||
                          targetUrl.contains('playlist') ||
                          targetUrl.contains('/hls/');

    if (isEmbed && !isDirectMedia) {
      return false;
    }

    if (isM3U8 == false && !isDirectMedia) {
      return false;
    }

    return true;
  }
}
