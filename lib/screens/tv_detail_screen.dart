import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:caffeine_tv/screens/actor_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:caffeine_tv/services/bookmark_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/services/ad_service.dart';

class TvDetailScreen extends StatefulWidget {
  const TvDetailScreen({super.key, required this.tvId});

  final int tvId;

  @override
  State<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends State<TvDetailScreen> {
  final ApiService _api = ApiService();
  TvShowDetail? _show;
  Map<int, TvSeasonDetailResponse>? _seasons;
  int? _selectedSeason;
  List<TvListItem>? _recommendations;
  CreditsResponse? _credits;
  final BookmarkService _bookmarkService = BookmarkService();
  final WatchHistoryService _historyService = WatchHistoryService();
  bool _isFavorite = false;
  String? _error;
  Map<String, dynamic>? _lastWatched;
  List<Map<String, dynamic>>? _seasonHistory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final show = await _api.fetchTvDetail(widget.tvId);
      List<TvListItem>? recs;
      CreditsResponse? credits;
      Map<String, dynamic>? lastWatched;

      // Fetch recommendations, credits and history in parallel
      await Future.wait([
        _api.fetchTvRecommendations(widget.tvId).then((r) => recs = r.results).catchError((_) => recs = []),
        _api.fetchTvCredits(widget.tvId).then((c) => credits = c).catchError((_) => credits = CreditsResponse(id: widget.tvId, cast: [])),
        WatchHistoryService().getLastWatchedEpisodeForShow(widget.tvId).then((h) => lastWatched = h),
      ]);

      if (mounted) {
        setState(() {
          _show = show;
          _seasons = {};
          _lastWatched = lastWatched;
          if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) {
            // Default to last watched season or Season 1
            _selectedSeason = lastWatched?['season_num'] ?? 1;
          }
          _recommendations = recs;
          _credits = credits;
        });
        if (_selectedSeason != null) _loadSeason(_selectedSeason!);
        _checkFavorite();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSeason(int num) async {
    try {
      final results = await Future.wait([
        _api.fetchSeasonDetail(widget.tvId, num),
        _historyService.getHistory(mediaType: 'tv', includeCompleted: true),
      ]);

      final detail = results[0] as TvSeasonDetailResponse;
      final history = results[1] as List<Map<String, dynamic>>;
      
      final currentSeasonHistory = history.where((h) => h['media_id'] == widget.tvId && h['season'] == num).toList();

      if (mounted) {
        setState(() {
          _seasons![num] = detail;
          _seasonHistory = currentSeasonHistory;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkFavorite() async {
    final isFav = await _bookmarkService.isBookmarked(widget.tvId, false);
    if (mounted) setState(() => _isFavorite = isFav);
  }

  Future<void> _toggleFavorite() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to favorite')),
      );
      return;
    }
    
    try {
      await _bookmarkService.toggleBookmark(_show!, false);
      setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update favorites: $e')),
        );
      }
    }
  }

  Widget _buildUpNextButton(double Function(double) s) {
    if (_show == null) return const SizedBox.shrink();
    
    int nextSeason = 1;
    int nextEpisode = 1;
    String label = 'PLAY';
    int? nextEpisodeId;

    if (_lastWatched != null) {
      final season = _lastWatched!['season'] as int? ?? 1;
      final episode = _lastWatched!['episode'] as int? ?? 1;
      final elapsed = _lastWatched!['elapsed'] as int? ?? 0;
      final total = elapsed + (_lastWatched!['remaining'] as int? ?? 0);
      
      final isFinished = total > 0 && (elapsed / total) >= 0.95;
      final progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
      
      if (!isFinished) {
          nextSeason = season;
          nextEpisode = episode;
          label = 'CONTINUE S$season E$episode';
          return _ActionBtn(
            label: label,
            icon: Icons.play_arrow,
            isPrimary: true,
            progress: progress,
            onTap: () => _handlePlay(season, episode, _lastWatched!['id'] as int, null, elapsed: elapsed),
            s: s,
            autofocus: true,
          );
        } else {
        // Find next episode
        final currentSeasonDetail = _seasons?[season];
        if (currentSeasonDetail != null) {
          if (episode < currentSeasonDetail.episodes.length) {
            final nextEp = currentSeasonDetail.episodes[episode]; // episode is 0-indexed here
            nextSeason = season;
            nextEpisode = nextEp.episodeNumber;
            nextEpisodeId = nextEp.id;
            label = 'WATCH NEXT S$nextSeason E$nextEpisode';
          } else if (season < (_show?.numberOfSeasons ?? 0)) {
            nextSeason = season + 1;
            nextEpisode = 1;
            // We don't have the next season's episode details yet, so episodeId will be null
            label = 'WATCH NEXT S$nextSeason E1';
          } else {
            label = 'PLAY S1 E1';
            nextSeason = 1;
            nextEpisode = 1;
            // We don't have the first season's episode details yet, so episodeId will be null
          }
        } else {
          // Fallback if current season detail isn't in memory
          // We can at least guess it's the next episode
          nextSeason = season;
          nextEpisode = episode + 1;
          label = 'WATCH NEXT';
        }
      }
    }

    return _ActionBtn(
      label: label,
      icon: Icons.play_circle_outline,
      isPrimary: true,
      onTap: () => _handlePlay(nextSeason, nextEpisode, nextEpisodeId, null),
      s: s,
      autofocus: true,
    );
  }

  void _handlePlay(int season, int episode, int? episodeId, String? episodeTitle, {int elapsed = 0}) async {
    if (elapsed > 0) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
          content: Text('Do you want to resume from ${Duration(seconds: elapsed).toString().split('.').first}?', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('START OVER', style: TextStyle(color: Color(0xFFEC1D24))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEC1D24)),
              child: const Text('RESUME'),
            ),
          ],
        ),
      );

      if (resume == null) return;
      
      if (resume) {
        _playEpisode(season, episode, episodeId, episodeTitle, startPosition: Duration(seconds: elapsed));
      } else {
        _playEpisode(season, episode, episodeId, episodeTitle, startPosition: Duration.zero);
      }
    } else {
      _playEpisode(season, episode, episodeId, episodeTitle);
    }
  }

  void _playEpisode(int season, int episode, int? episodeId, String? episodeTitle, {Duration? startPosition}) async {
    if (_show == null) return;

    // Show interstitial ad before navigation
    await AdService.instance.showInterstitialAd();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLoaderScreen(
          tvShow: _show!,
          season: season,
          episode: episode,
          episodeId: episodeId,
          episodeName: episodeTitle,
          startPosition: startPosition,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() => _error = null); _load(); }, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_show == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F14),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final show = _show!;
    final backdropUrl = show.backdropPath != null && show.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${show.backdropPath}'
        : null;
    final s = (double v) => (v * MediaQuery.of(context).size.width) / 1920;
    final seasonDetail = _selectedSeason != null && _seasons != null
        ? _seasons![_selectedSeason!]
        : null;
    final episodes = seasonDetail?.episodes ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // secondary.dark.background
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Backdrop
          if (backdropUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.6,
                child: CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const ColoredBox(color: Colors.black),
                  errorWidget: (context, url, error) => const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          // Horizontal Gradient (accent.heroOverlay)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withOpacity(0.95),
                    const Color(0xFF7F1D1D).withOpacity(0.6), // primary.900
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // Vertical Fade
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
          ),
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(s(48)),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(s(24)),
                              child: BackdropFilter(
                                filter: ColorFilter.mode(Colors.black.withOpacity(0.35), BlendMode.darken),
                                child: Container(
                                  padding: EdgeInsets.all(s(40)),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(s(24)),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                      width: s(1.5),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (show.posterPath != null && show.posterPath!.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(s(16)),
                                          child: CachedNetworkImage(
                                            imageUrl: '$tmdbImageBaseUrl/w500${show.posterPath}',
                                            width: s(280),
                                            height: s(420),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      SizedBox(width: s(48)),
                                      Expanded(
                                        child: Focus(
                                          descendantsAreFocusable: false,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Title (H1 style)
                                              Text(
                                                show.name?.toUpperCase() ?? 'TV SHOW',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: s(90),
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: s(-2),
                                                  height: 0.9,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black.withOpacity(0.5),
                                                      offset: Offset(0, s(4)),
                                                      blurRadius: s(10),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(height: s(24)),
                                              // Meta Row
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEC1D24), // brand red
                                                      borderRadius: BorderRadius.circular(s(4)),
                                                    ),
                                                    child: Text(
                                                      'IMDb ${(show.voteAverage ?? 0.0).toStringAsFixed(1)}',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: s(18),
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: s(24)),
                                                  Text(
                                                    show.firstAirDate?.split('-').first ?? '',
                                                    style: TextStyle(color: Colors.white70, fontSize: s(20)),
                                                  ),
                                                  SizedBox(width: s(24)),
                                                  Text(
                                                    '${show.numberOfSeasons ?? 0} Seasons',
                                                    style: TextStyle(color: Colors.white70, fontSize: s(20)),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: s(32)),
                                              // Overview
                                              SizedBox(
                                                width: s(900),
                                                child: Text(
                                                  show.overview ?? '',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.85),
                                                    fontSize: s(22),
                                                    fontWeight: FontWeight.w400,
                                                    height: 1.6,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: s(64)),
                            // Action Buttons (Favorite/Share) - Play is handled per episode
                            Row(
                              children: [
                                _buildUpNextButton(s),
                                SizedBox(width: s(24)),
                                _ActionBtn(
                                  label: _isFavorite ? 'FAVOURITED' : 'FAVOURITE',
                                  icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                                  isPrimary: false, // Favorite is secondary now
                                  onTap: _toggleFavorite,
                                  s: s,
                                ),
                                SizedBox(width: s(24)),
                                _ActionBtn(
                                  label: 'SHARE',
                                  icon: Icons.share_outlined,
                                  isPrimary: false,
                                  onTap: () {},
                                  s: s,
                                ),
                              ],
                            ),
                            SizedBox(height: s(64)),
                  const SizedBox(height: 24),
                            if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) ...[
                              _SectionHeader(title: 'SEASONS', s: s),
                              SizedBox(height: s(24)),
                              _SeasonSelector(
                                currentSeason: _selectedSeason!,
                                totalSeasons: show.numberOfSeasons!,
                                s: s,
                                onSelected: (n) {
                                  setState(() {
                                    _selectedSeason = n;
                                    _loadSeason(n);
                                  });
                                },
                              ),
                              SizedBox(height: s(48)),
                            ],
                            _SectionHeader(title: 'EPISODES', s: s),
                            SizedBox(height: s(24)),
                            if (episodes.isEmpty)
                              Center(child: Padding(padding: EdgeInsets.symmetric(vertical: s(48)), child: Text('Select a season to view episodes', style: TextStyle(color: Colors.white54, fontSize: s(20)))))
                            else
                              Column(
                                children: episodes.map((ep) {
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: s(16)),
                                    child: Focus(
                                      descendantsAreFocusable: false,
                                      onKeyEvent: (node, event) {
                                        if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                        if (event.logicalKey == LogicalKeyboardKey.enter ||
                                            event.logicalKey == LogicalKeyboardKey.select) {
                                          if (true) {
                                              final history = _seasonHistory?.firstWhere(
                                                (h) => h['episode'] == ep.episodeNumber,
                                                orElse: () => {},
                                              );
                                              final elapsed = history != null && history.isNotEmpty ? history['elapsed'] as int? ?? 0 : 0;
                                              _handlePlay(ep.seasonNumber, ep.episodeNumber, ep.id, ep.name, elapsed: elapsed);
                                          }
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final focused = Focus.of(context).hasFocus;
                                          return GestureDetector(
                                            onTap: () {
                                              if (true) {
                                                final history = _seasonHistory?.firstWhere(
                                                  (h) => h['episode'] == ep.episodeNumber,
                                                  orElse: () => {},
                                                );
                                                final elapsed = history != null && history.isNotEmpty ? history['elapsed'] as int? ?? 0 : 0;
                                                _handlePlay(ep.seasonNumber, ep.episodeNumber, ep.id, ep.name, elapsed: elapsed);
                                              }
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              decoration: BoxDecoration(
                                                color: focused ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                                                borderRadius: BorderRadius.circular(s(16)),
                                                border: Border.all(
                                                  color: focused ? Colors.white : Colors.white.withOpacity(0.1),
                                                  width: s(1.5),
                                                ),
                                                boxShadow: focused
                                                    ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)]
                                                    : [],
                                              ),
                                              child: Stack(
                                                children: [
                                                  Padding(
                                                    padding: EdgeInsets.all(s(16)),
                                                    child: Row(
                                                      children: [
                                                        if (ep.stillPath != null && ep.stillPath!.isNotEmpty)
                                                          ClipRRect(
                                                            borderRadius: BorderRadius.circular(s(12)),
                                                            child: CachedNetworkImage(
                                                              imageUrl: '$tmdbImageBaseUrl/w300${ep.stillPath}',
                                                              width: s(200),
                                                              height: s(112),
                                                              fit: BoxFit.cover,
                                                            ),
                                                          )
                                                        else
                                                          Container(
                                                            width: s(200),
                                                            height: s(112),
                                                            decoration: BoxDecoration(
                                                              color: Colors.white10,
                                                              borderRadius: BorderRadius.circular(s(12)),
                                                            ),
                                                            child: Icon(Icons.tv, color: Colors.white38, size: s(40)),
                                                          ),
                                                        SizedBox(width: s(32)),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      'E${ep.episodeNumber} - ${ep.name ?? ""}',
                                                                      style: TextStyle(
                                                                        color: Colors.white,
                                                                        fontSize: s(22),
                                                                        fontWeight: focused ? FontWeight.bold : FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final history = _seasonHistory?.firstWhere(
                                                                        (h) => h['episode'] == ep.episodeNumber,
                                                                        orElse: () => {},
                                                                      );
                                                                      if (history == null || history.isEmpty) return const SizedBox.shrink();
                                                                      
                                                                      final elapsed = history['elapsed'] as int? ?? 0;
                                                                      final remaining = history['remaining'] as int? ?? 0;
                                                                      final total = elapsed + remaining;
                                                                      if (total > 0 && (elapsed / total) >= 0.9) {
                                                                        return Icon(Icons.check_circle, color: Colors.green, size: s(24));
                                                                      }
                                                                      return const SizedBox.shrink();
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                              SizedBox(height: s(8)),
                                                              if (ep.overview != null && ep.overview!.isNotEmpty)
                                                                Text(
                                                                  ep.overview!,
                                                                  style: TextStyle(
                                                                    color: focused ? Colors.white.withOpacity(0.9) : Colors.white54,
                                                                    fontSize: s(16),
                                                                    height: 1.4,
                                                                  ),
                                                                  maxLines: 2,
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (focused)
                                                          Padding(
                                                            padding: EdgeInsets.only(right: s(16)),
                                                            child: Icon(Icons.play_circle_fill, color: Colors.white, size: s(48)),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Progress bar for episodes
                                                  Builder(
                                                    builder: (context) {
                                                      final history = _seasonHistory?.firstWhere(
                                                        (h) => h['episode'] == ep.episodeNumber,
                                                        orElse: () => {},
                                                      );
                                                      if (history == null || history.isEmpty) return const SizedBox.shrink();
                                                      
                                                      final elapsed = history['elapsed'] as int? ?? 0;
                                                      final remaining = history['remaining'] as int? ?? 0;
                                                      final total = elapsed + remaining;
                                                      if (total <= 0) return const SizedBox.shrink();
                                                      
                                                      final progress = (elapsed / total).clamp(0.0, 1.0);
                                                      
                                                      return Positioned(
                                                        left: s(16),
                                                        right: s(16),
                                                        bottom: 0,
                                                        child: Container(
                                                          height: s(4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.white10,
                                                            borderRadius: BorderRadius.circular(s(2)),
                                                          ),
                                                          child: FractionallySizedBox(
                                                            alignment: Alignment.centerLeft,
                                                            widthFactor: progress,
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFEC1D24),
                                                                borderRadius: BorderRadius.circular(s(2)),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }
                                      ),
                                    ),
                                  );
                                },
                              ).toList(),
                              ),
                            if (_credits != null && _credits!.cast.isNotEmpty) ...[
                              SizedBox(height: s(64)),
                              _SectionHeader(title: 'CAST', s: s),
                              SizedBox(height: s(24)),
                              SizedBox(
                                height: s(220),
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _credits!.cast.length,
                                  itemBuilder: (context, index) {
                                    final actor = _credits!.cast[index];
                                    return Focus(
                                      onKeyEvent: (_, event) {
                                        if (event is KeyDownEvent &&
                                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                             event.logicalKey == LogicalKeyboardKey.select)) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => ActorScreen(personId: actor.id),
                                            ),
                                          );
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final focused = Focus.of(context).hasFocus;
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) => ActorScreen(personId: actor.id),
                                                ),
                                              );
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              width: s(160),
                                              margin: EdgeInsets.only(right: s(32)),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(s(16)),
                                                border: Border.all(
                                                  color: focused ? Colors.white : Colors.white.withOpacity(0.05),
                                                  width: s(2),
                                                ),
                                                color: focused ? Colors.white.withOpacity(0.1) : Colors.transparent,
                                              ),
                                              padding: EdgeInsets.all(s(8)),
                                              child: Column(
                                                children: [
                                                  ClipOval(
                                                    child: actor.profilePath != null
                                                        ? CachedNetworkImage(
                                                            imageUrl: '$tmdbImageBaseUrl/w185${actor.profilePath}',
                                                            width: s(110),
                                                            height: s(110),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : Container(
                                                            width: s(110),
                                                            height: s(110),
                                                            color: Colors.white12,
                                                            child: Icon(Icons.person, color: Colors.white54, size: s(48)),
                                                          ),
                                                  ),
                                                  SizedBox(height: s(12)),
                                                  Text(
                                                    actor.name,
                                                    style: TextStyle(
                                                      color: focused ? Colors.white : Colors.white.withOpacity(0.8),
                                                      fontSize: s(16),
                                                      fontWeight: focused ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                             if (_recommendations != null && _recommendations!.isNotEmpty) ...[
                              SizedBox(height: s(64)),
                              _SectionHeader(title: 'MORE LIKE THIS', s: s),
                              SizedBox(height: s(24)),
                              SizedBox(
                                height: s(300),
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _recommendations!.length,
                                  itemBuilder: (context, index) {
                                    final rec = _recommendations![index];
                                    return PosterCard(
                                      posterPath: rec.posterPath,
                                      title: rec.name ?? '',
                                      onTap: () {
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: rec.id)),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final double Function(double) s;

  const _SectionHeader({required this.title, required this.s});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white,
        fontSize: s(28),
        fontWeight: FontWeight.bold,
        letterSpacing: s(1.2),
      ),
    );
  }
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;
  final double Function(double) s;
  final bool autofocus;
  final double? progress;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    required this.s,
    this.autofocus = false,
    this.progress,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  double _scale = 1.0;

  void _handleTap() {
    setState(() => _scale = 1.08);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scale = 1.0);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutBack,
      child: Focus(
        autofocus: widget.autofocus,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select)) {
            _handleTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: _handleTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: widget.isPrimary 
                      ? (focused ? Colors.white : Colors.white.withOpacity(0.15))
                      : (focused ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.08)),
                  borderRadius: BorderRadius.circular(widget.s(12)),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white.withOpacity(0.15),
                    width: widget.s(focused ? 1.5 : 1),
                  ),
                  boxShadow: focused ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: widget.s(15),
                      spreadRadius: widget.s(2),
                    )
                  ] : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.s(8)),
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: widget.s(32), vertical: widget.s(16)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.icon, 
                              color: widget.isPrimary ? (focused ? Colors.black : Colors.white) : Colors.white,
                              size: widget.s(28),
                            ),
                            SizedBox(width: widget.s(12)),
                            Text(
                              widget.label,
                              style: TextStyle(
                                color: widget.isPrimary ? (focused ? Colors.black : Colors.white) : Colors.white,
                                fontSize: widget.s(18),
                                fontWeight: FontWeight.bold,
                                letterSpacing: widget.s(1.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.progress != null && widget.progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: widget.s(4),
                            color: Colors.white.withOpacity(0.2),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: widget.progress!,
                              child: Container(color: focused ? Colors.black : const Color(0xFFEC1D24)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }
}

class _SeasonSelector extends StatefulWidget {
  final int currentSeason;
  final int totalSeasons;
  final double Function(double) s;
  final ValueChanged<int> onSelected;

  const _SeasonSelector({
    required this.currentSeason,
    required this.totalSeasons,
    required this.s,
    required this.onSelected,
  });

  @override
  State<_SeasonSelector> createState() => _SeasonSelectorState();
}

class _SeasonSelectorState extends State<_SeasonSelector> {
  bool _isFocused = false;

  void _showPicker() {
    showDialog(
      context: context,
      builder: (context) => _SeasonPicker(
        totalSeasons: widget.totalSeasons,
        currentSeason: widget.currentSeason,
        s: widget.s,
        onSelected: widget.onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _showPicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(12)),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(s(12)),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white.withOpacity(0.15),
              width: s(1.5),
            ),
            boxShadow: _isFocused
                ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SEASON ${widget.currentSeason}',
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: s(20),
                  fontWeight: FontWeight.bold,
                  letterSpacing: s(1),
                ),
              ),
              SizedBox(width: s(16)),
              Icon(
                Icons.arrow_drop_down,
                color: _isFocused ? Colors.black : Colors.white,
                size: s(24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonPicker extends StatelessWidget {
  final int totalSeasons;
  final int currentSeason;
  final double Function(double) s;
  final ValueChanged<int> onSelected;

  const _SeasonPicker({
    required this.totalSeasons,
    required this.currentSeason,
    required this.s,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s(16))),
      child: Container(
        width: s(400),
        padding: EdgeInsets.all(s(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELECT SEASON',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: s(16),
                fontWeight: FontWeight.bold,
                letterSpacing: s(2),
              ),
            ),
            SizedBox(height: s(24)),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: totalSeasons,
                itemBuilder: (context, i) {
                  final num = i + 1;
                  final selected = num == currentSeason;
                  return _SeasonItem(
                    num: num,
                    selected: selected,
                    s: s,
                    onTap: () {
                      onSelected(num);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonItem extends StatefulWidget {
  final int num;
  final bool selected;
  final double Function(double) s;
  final VoidCallback onTap;

  const _SeasonItem({
    required this.num,
    required this.selected,
    required this.s,
    required this.onTap,
  });

  @override
  State<_SeasonItem> createState() => _SeasonItemState();
}

class _SeasonItemState extends State<_SeasonItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.only(bottom: s(8)),
          padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(16)),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : (widget.selected ? const Color(0xFFDC2626).withOpacity(0.2) : Colors.transparent),
            borderRadius: BorderRadius.circular(s(8)),
            border: Border.all(
              color: _isFocused ? Colors.white : (widget.selected ? const Color(0xFFDC2626) : Colors.transparent),
              width: s(2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Season ${widget.num}',
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: s(20),
                  fontWeight: widget.selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (widget.selected)
                Icon(
                  Icons.check,
                  color: _isFocused ? Colors.black : const Color(0xFFDC2626),
                  size: s(20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
