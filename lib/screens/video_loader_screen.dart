import 'dart:ui';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/models/provider_load_state.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/subtitle_service.dart';
import 'package:caffeine_tv/models/sub_languages.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/widgets/provider_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:better_player/better_player.dart';

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
    {'code': 'vidsrc', 'name': 'Vidsrc'},
    {'code': 'vidzee', 'name': 'Vidzee'},
  ];

  late List<ProviderLoadState> _providerStates;
  int _currentProviderIndex = 0;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    
    // Prioritize preferred provider if specified
    if (widget.preferredProvider != null) {
      final prefIndex = _providers.indexWhere((p) => p['code'] == widget.preferredProvider);
      if (prefIndex != -1) {
        final pref = _providers.removeAt(prefIndex);
        _providers.insert(0, pref);
      }
    }

    _providerStates = _providers.map((p) => ProviderLoadState(
      codeName: p['code']!,
      fullName: p['name']!,
      status: ProviderStatus.pending,
    )).toList();

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
      debugPrint('[VideoLoader] 📺 TV Show: S${widget.season}E${widget.episode}');
      if (widget.season == null || widget.episode == null) {
        debugPrint('[VideoLoader] ❌ Cannot load TV stream: season or episode missing');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not determine which episode to play')),
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

      debugPrint('[VideoLoader] 🔍 Trying provider: $providerName ($providerCode) [${i + 1}/${_providers.length}]');

      try {
        core.ProviderStreamResponse response;
        if (widget.movie != null) {
          response = await _api.fetchMovieStream(widget.movie!.id, provider: providerCode);
        } else {
          response = await _api.fetchTvStream(
            widget.tvShow!.id, 
            widget.season!, 
            widget.episode!, 
            provider: providerCode
          );
        }

        if (response.success && response.links != null && response.links!.isNotEmpty) {
          debugPrint('[VideoLoader] ✅ Found ${response.links!.length} stream(s) from $providerName');
          if (!mounted) return;

          List<BetterPlayerSubtitlesSource> subs = [];
          
          // 1. Process internal subtitles from provider
          if (response.links!.first.subtitles.isNotEmpty) {
            debugPrint('[VideoLoader] 📝 Found ${response.links!.first.subtitles.length} internal subtitles');
            subs.addAll(response.links!.first.subtitles.map((s) => BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.network,
              name: s.label,
              urls: [s.file],
              selectedByDefault: s.isDefault ?? false,
            )));
          } else {
            debugPrint('[VideoLoader] ℹ️ No internal subtitles from provider');
          }

          // 2. Open Subtitles 
          if (_settings.useExternalSubtitles && _settings.opensubtitlesKey.isNotEmpty) {
            debugPrint('[VideoLoader] 🔍 External subtitles enabled. Checking Open Subtitles...');
            try {
              String? imdbId;
              if (widget.movie != null) {
                imdbId = await _api.fetchMovieExternalIds(widget.movie!.id);
              } else {
                imdbId = await _api.fetchTvExternalIds(widget.tvShow!.id);
              }

              debugPrint('[VideoLoader] 🆔 IMDB ID: $imdbId');

              if (imdbId != null && imdbId.isNotEmpty) {
                final langCode = _settings.language;
                debugPrint('[VideoLoader] 🌐 Searching for language: $langCode');
                final extSubs = await _subtitleService.searchSubtitles(
                  imdbId: imdbId, 
                  languageCode: langCode, 
                  apiKey: _settings.opensubtitlesKey,
                  seasonNumber: widget.season,
                  episodeNumber: widget.episode,
                );

                if (extSubs.isNotEmpty) {
                  debugPrint('[VideoLoader] ✅ Found ${extSubs.length} Open Subtitles');
                  final fileId = extSubs.first.attr?.files?.first.fileId;
                  if (fileId != null) {
                    debugPrint('[VideoLoader] 📥 Downloading subtitle file: $fileId');
                    final downloadUrl = await _subtitleService.downloadSubtitle(fileId, _settings.opensubtitlesKey);
                    if (downloadUrl != null) {
                       debugPrint('[VideoLoader] ✨ External subtitle added: $downloadUrl');
                       subs.add(BetterPlayerSubtitlesSource(
                        type: BetterPlayerSubtitlesSourceType.network,
                        name: 'OpenSubtitles ($langCode)',
                        urls: [downloadUrl],
                      ));
                    }
                  }
                } else {
                  debugPrint('[VideoLoader] ℹ️ No Open Subtitles found for $imdbId in $langCode');
                }
              }
            } catch (e) {
              debugPrint('[VideoLoader] ⚠️ External subtitle search failed: $e');
            }
          } else {
            debugPrint('[VideoLoader] ℹ️ External subtitles disabled or API key missing');
          }

          debugPrint('[VideoLoader] 🏁 Total subtitles collected: ${subs.length}');

          setState(() {
            _providerStates[i].status = ProviderStatus.success;
            _isDone = true;
          });

          debugPrint('[VideoLoader] 🚀 Launching PlayerScreen with URL: ${response.links!.first.url}');
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
          debugPrint('[VideoLoader] ❌ Provider $providerName returned no links or success=false');
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
      debugPrint('[VideoLoader] 🚫 All providers failed to return a stream for $mediaName');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stream available from any provider')),
      );
      Navigator.of(context).pop();
    }
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    final s = (double v) => _scale(context, v);
    final backdropPath = widget.movie?.backdropPath ?? widget.tvShow?.backdropPath;
    final title = widget.movie?.title ?? widget.tvShow?.name ?? 'Loading...';
    final subtitle = widget.tvShow != null 
        ? 'Season ${widget.season} • Episode ${widget.episode}${widget.episodeName != null ? " • ${widget.episodeName}" : ""}'
        : widget.movie?.releaseDate?.split('-').first ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Backdrop Background
          if (backdropPath != null)
            CachedNetworkImage(
              imageUrl: '$tmdbImageBaseUrl/original$backdropPath',
              fit: BoxFit.cover,
            ),
          
          // 2. Blur Layer
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: Colors.black.withOpacity(0.65),
            ),
          ),

          // 3. Glass Loading Card
          Center(
            child: Container(
              width: s(1000),
              padding: EdgeInsets.all(s(48)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(s(40)),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: s(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: s(60),
                    spreadRadius: s(10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(s(40)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: s(48)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(42),
                              fontWeight: FontWeight.w900,
                              letterSpacing: s(2),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (subtitle.isNotEmpty) ...[
                            SizedBox(height: s(12)),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: s(24),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          SizedBox(height: s(48)),
                          ProviderLoadingWidget(
                            providers: _providerStates,
                            currentIndex: _currentProviderIndex,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
