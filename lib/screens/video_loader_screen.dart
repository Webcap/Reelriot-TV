import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:caffeine_tv/models/provider_load_state.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/widgets/provider_loading_widget.dart';
import 'package:flutter/material.dart';

class VideoLoaderScreen extends StatefulWidget {
  final core.MovieDetail? movie;
  final core.TvShowDetail? tvShow;
  final int? season;
  final int? episode;
  final String? episodeName;
  final Duration? startPosition;

  const VideoLoaderScreen({
    this.movie,
    this.tvShow,
    this.season,
    this.episode,
    this.episodeName,
    this.startPosition,
    super.key,
  });

  @override
  State<VideoLoaderScreen> createState() => _VideoLoaderScreenState();
}

class _VideoLoaderScreenState extends State<VideoLoaderScreen> {
  final ApiService _api = ApiService();
  final WatchHistoryService _historyService = WatchHistoryService();
  
  final List<Map<String, String>> _providers = [
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

      // Use passed-in start position; otherwise look up from DB
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
          setState(() {
            _providerStates[i].status = ProviderStatus.success;
            _isDone = true;
          });

          debugPrint('[VideoLoader] 🚀 Launching PlayerScreen with URL: ${response.links!.first.url}');
          // Navigate to player
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
                episodeName: widget.episodeName,
                startPosition: startPos,
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

    // If all failed
    if (mounted && !_isDone) {
      debugPrint('[VideoLoader] 🚫 All providers failed to return a stream for $mediaName');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stream available from any provider')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ProviderLoadingWidget(
          providers: _providerStates,
          currentIndex: _currentProviderIndex,
        ),
      ),
    );
  }
}
