import 'package:caffeine_core/caffeine_core.dart' as core;
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
import 'package:reelriot_tv/utils/video_utils.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelriot_tv/utils/wakelock_manager.dart';

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
    {'code': 'vixsrc', 'name': 'Vixsrc'},
    {'code': 'vidsrcsu', 'name': 'Vidsrc.su'},
    {'code': 'vidzee', 'name': 'Vidzee'},
    {'code': 'flixhq', 'name': 'FlixHQ'},
  ];

  late List<ProviderLoadState> _providerStates;
  int _currentProviderIndex = 0;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    WakelockManager.enable();
    OutageService.instance.pause();

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

  void _loadVideo() async {
    final mediaId = widget.movie?.id ?? widget.tvShow?.id;
    final mediaName = widget.movie?.title ?? widget.tvShow?.name;
    debugPrint('[VideoLoader] 🎬 Loading media: $mediaName (ID: $mediaId)');
    if (widget.tvShow != null) {
      debugPrint(
        '[VideoLoader] 📺 TV Show: S${widget.season}E${widget.episode}',
      );
      if (widget.season == null || widget.episode == null) {
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

    for (int i = 0; i < _providers.length; i++) {
      if (!mounted) return;

      Duration? startPos;
      if (i == 0) {
        if (widget.startPosition != null) {
          startPos = widget.startPosition;
        } else {
          startPos = await _historyService.getSavedProgress(
            mediaId!,
            widget.movie != null,
            season: widget.season,
            episode: widget.episode,
          );
        }
      }

      final providerCode = _providers[i]['code']!;
      final providerName = _providers[i]['name']!;

      setState(() {
        _currentProviderIndex = i;
        _providerStates[i].status = ProviderStatus.loading;
      });

      debugPrint(
        '[VideoLoader] 🔍 Trying provider: $providerName ($providerCode) [${i + 1}/${_providers.length}]',
      );

      try {
        core.ProviderStreamResponse response;
        if (widget.movie != null) {
          response = await _api.fetchMovieStream(
            widget.movie!.id,
            provider: providerCode,
          );
        } else {
          response = await _api.fetchTvStream(
            widget.tvShow!.id,
            widget.season!,
            widget.episode!,
            provider: providerCode,
          );
        }

        if (response.success &&
            response.links != null &&
            response.links!.isNotEmpty) {
          debugPrint(
            '[VideoLoader] ✅ Found ${response.links!.length} stream(s) from $providerName',
          );
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
                seasonNumber: widget.season,
                episodeNumber: widget.episode,
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

          setState(() {
            _providerStates[i].status = ProviderStatus.success;
            _isDone = true;
          });

          debugPrint(
            '[VideoLoader] 🚀 Launching PlayerScreen with URL: ${response.links!.first.url}',
          );
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => PlayerScreen(
                url: response.links!.first.url,
                title: widget.movie?.title ?? widget.tvShow?.name ?? 'Video',
                item: widget.movie ?? widget.tvShow,
                isMovie: widget.movie != null,
                season: widget.season,
                episode: widget.episode,
                episodeId: widget.episodeId,
                episodeName: widget.episodeName,
                startPosition: startPos,
                providerCode: providerCode,
                allProviders: _providers,
                headers: response.links!.first.headers,
                externalSubtitles: subs,
              ),
            ),
          );
          return;
        } else {
          debugPrint(
            '[VideoLoader] ❌ Provider $providerName returned no links or success=false',
          );
          setState(() {
            _providerStates[i].status = ProviderStatus.failed;
          });
        }
      } catch (e) {
        debugPrint('[VideoLoader] ⚠️ Error with provider $providerName: $e');
        if (mounted) {
          setState(() {
            _providerStates[i].status = ProviderStatus.failed;
          });
        }
      }
    }

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
}
