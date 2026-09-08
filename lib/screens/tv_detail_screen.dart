import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/screens/video_loader_screen.dart';
import 'package:reelriot_tv/screens/actor_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:reelriot_tv/services/bookmark_service.dart';
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/widgets/context_menu_dialog.dart';
import 'package:reelriot_tv/widgets/add_watch_menu.dart';
import 'package:reelriot_tv/utils/auth_error_utils.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/widgets/native_ad_banner.dart';
import 'package:reelriot_tv/widgets/full_screen_status.dart';
import 'package:reelriot_tv/widgets/hero_badge.dart';
import '../models/ad.dart' as model;

class TvDetailScreen extends StatefulWidget {
  const TvDetailScreen({super.key, required this.tvId});

  final int tvId;

  @override
  State<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends State<TvDetailScreen> {
  final ApiService _api = ApiService();

  Future<void> _addEpisodeWatch(TvEpisode ep, {DateTime? watchedAt, bool unknownDate = false}) async {
    if (_show == null) return;
    await _historyService.addWatch(
      item: _show!,
      isMovie: false,
      season: ep.seasonNumber,
      episode: ep.episodeNumber,
      episodeName: ep.name,
      watchedAt: watchedAt,
      unknownDate: unknownDate,
    );
    if (mounted) {
      setState(() => _recentlyCompletedIds.add(ep.id));
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _recentlyCompletedIds.remove(ep.id));
      });
    }
    _load(); // Refresh season history
  }

  Future<void> _showEpisodeWatchHistory(TvEpisode ep, double Function(double) s) async {
    if (_show == null) return;
    final events = await _historyService.getWatchEvents(
      mediaId: _show!.id,
      isMovie: false,
      season: ep.seasonNumber,
      episode: ep.episodeNumber,
    );
    if (!mounted) return;

    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No watches logged yet')),
      );
      return;
    }

    ContextMenuDialog.show(
      context: context,
      title: 'Watch History',
      s: s,
      items: events.map((e) {
        final watchedAt = e['watched_at'] as String?;
        final label = watchedAt != null ? _formatDate(watchedAt) : 'Unknown date';
        return ContextMenuItem(
          label: 'Remove: $label',
          icon: Icons.delete_outline,
          color: Colors.redAccent,
          onTap: () async {
            await _historyService.removeWatchEvent(e['id'] as String);
            _load();
          },
        );
      }).toList(),
    );
  }

  void _showEpisodeContextMenu(TvEpisode ep, bool isWatched) {
    s(double v) => _scale(context, v);
    ContextMenuDialog.show(
      context: context,
      title: 'E${ep.episodeNumber} - ${ep.name ?? ""}',
      s: s,
      items: [
        ContextMenuItem(
          label: 'Add Another Watch',
          icon: Icons.check_circle_outline,
          onTap: () {
            final releaseDate = ep.airDate != null ? DateTime.tryParse(ep.airDate!) : null;
            AddWatchMenu.show(
              context: context,
              title: ep.name ?? 'Episode ${ep.episodeNumber}',
              s: s,
              releaseDate: releaseDate,
              onPick: ({watchedAt, unknownDate = false}) =>
                  _addEpisodeWatch(ep, watchedAt: watchedAt, unknownDate: unknownDate),
            );
          },
        ),
        ContextMenuItem(
          label: 'Watch History',
          icon: Icons.history_rounded,
          onTap: () => _showEpisodeWatchHistory(ep, s),
        ),
        ContextMenuItem(
          label: 'Mark Watched until here',
          icon: Icons.playlist_add_check,
          onTap: () async {
            if (_show == null) return;
            await _historyService.markUntilEpisodeAsComplete(
              item: _show!,
              season: ep.seasonNumber,
              untilEpisode: ep.episodeNumber,
              allEpisodes: _seasons?[ep.seasonNumber]?.episodes ?? [],
            );
            _load(); // Refresh history
          },
        ),
        if (isWatched)
          ContextMenuItem(
            label: 'Remove from History',
            icon: Icons.delete_outline,
            color: Colors.redAccent,
            onTap: () async {
              if (_show == null) return;
              await _historyService.removeFromHistory(
                id: _show!.id,
                isMovie: false,
                season: ep.seasonNumber,
                episode: ep.episodeNumber,
              );
              _load(); // Refresh season history
            },
          ),
      ],
    );
  }
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
  bool _isProcessing = false;
  final Set<int> _recentlyCompletedIds = {};
  model.Ad? _bannerAd;
  final ScrollController _scrollController = ScrollController();


  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // The primary action button autofocuses, and Flutter's focus system
  // auto-scrolls a newly-focused widget into view — with nothing focusable
  // above it (the title/badges are plain text), that scroll has nowhere to
  // go back to, so the page loads permanently scrolled past its own top.
  // Force it back to 0 once the content (and the autofocus it triggers)
  // has actually laid out.
  void _resetScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
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
        Supabase.instance.client
            .from('sponsorships')
            .select('*')
            .eq('is_active', true)
            .eq('placement', 'banner')
            .limit(1)
            .maybeSingle()
            .then((data) {
          if (data != null && mounted) {
            setState(() {
              _bannerAd = model.Ad.fromJson(data);
            });
          }
        }).catchError((_) {}),
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
        _resetScrollToTop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      await handleIfUnrecoverableAuthError(e);
    }
  }

  Future<void> _loadSeason(int num) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final results = await Future.wait([
        _api.fetchSeasonDetail(widget.tvId, num),
        if (user != null)
          _historyService.getSeasonProgress(widget.tvId, num)
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);

      final detail = results[0] as TvSeasonDetailResponse;
      final seasonHistory = List<Map<String, dynamic>>.from(results[1] as List);

      // The API doesn't carry TMDB episode ids — attach them locally from the
      // season detail response so episode_id-based lookups elsewhere still work.
      final episodeIdByNum = {for (final ep in detail.episodes) ep.episodeNumber: ep.id};
      for (final entry in seasonHistory) {
        entry['episode_id'] = episodeIdByNum[entry['episode_num']];
      }

      if (mounted) {
        setState(() {
          _seasons![num] = detail;
          _seasonHistory = seasonHistory;
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
      await handleIfUnrecoverableAuthError(e);
    }
  }

  Widget _buildUpNextButton(double Function(double) s) {
    if (_show == null) return const SizedBox.shrink();
    
    int nextSeason = 1;
    int nextEpisode = 1;
    String label = 'PLAY';
    int? nextEpisodeId;

    if (_lastWatched != null) {
      final season = _lastWatched!['season_num'] as int? ?? 1;
      final episode = _lastWatched!['episode_num'] as int? ?? 1;
      final elapsed = _lastWatched!['elapsed_ms'] as int? ?? 0;
      final total = _lastWatched!['duration_ms'] as int? ?? 0;
      
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
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      if (elapsed > 0) {
        final resume = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: DashboardTheme.surfaceRaised,
            title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
            content: Text('Do you want to resume from ${Duration(milliseconds: elapsed).toString().split('.').first}?', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('START OVER', style: TextStyle(color: DashboardTheme.signalRed)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: DashboardTheme.signalRed),
                child: const Text('RESUME'),
              ),
            ],
          ),
        );

        if (resume == null) return;
        
        if (resume) {
          _playEpisode(season, episode, episodeId, episodeTitle, startPosition: Duration(milliseconds: elapsed));
        } else {
          _playEpisode(season, episode, episodeId, episodeTitle, startPosition: Duration.zero);
        }
      } else {
        _playEpisode(season, episode, episodeId, episodeTitle);
      }
    } finally {
      _isProcessing = false;
      if (mounted) setState(() {});
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
    ).then((_) async {
      await Future.delayed(const Duration(seconds: 1));
      // Store current status to compare after load
      final oldHistory = _seasonHistory?.toList();
      await _load();
      
      if (episodeId != null && mounted) {
        // If it's now completed but wasn't before (or just refresh anyway for the polish)
        final isNowWatched = _seasonHistory?.any((h) => h['episode_id'] == episodeId) ?? false;
        final wasWatched = oldHistory?.any((h) => h['episode_id'] == episodeId) ?? false;
        
        if (isNowWatched && !wasWatched) {
          setState(() => _recentlyCompletedIds.add(episodeId));
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _recentlyCompletedIds.remove(episodeId));
          });
        }
      }
    });


  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return FullScreenError(
        message: 'This title couldn\'t be loaded',
        subtitle: _error!,
        onRetry: () {
          setState(() => _error = null);
          _load();
        },
      );
    }

    if (_show == null) {
      return const FullScreenLoading();
    }

    final show = _show!;
    final backdropUrl = show.backdropPath != null && show.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${show.backdropPath}'
        : null;
    double s(double v) => _scale(context, v);
    final seasonDetail = _selectedSeason != null && _seasons != null
        ? _seasons![_selectedSeason!]
        : null;
    final episodes = seasonDetail?.episodes ?? [];

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed cinematic backdrop — same scrim language as the home
          // hero, replacing the old poster + frosted-glass-card layout.
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropUrl != null)
                  CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (context, url) => ColoredBox(color: DashboardTheme.surface),
                    errorWidget: (context, url, error) => ColoredBox(color: DashboardTheme.surface),
                  )
                else
                  ColoredBox(color: DashboardTheme.surface),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: DashboardTheme.heroLeftScrim),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: DashboardTheme.heroBottomScrim),
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(horizontal: s(56), vertical: s(48)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: s(64)),
                  // Badges
                  Row(
                    children: [
                      HeroBadge(
                        label: 'HD',
                        color: Colors.white.withValues(alpha: 0.15),
                        borderColor: Colors.white24,
                      ),
                      SizedBox(width: s(14)),
                      HeroBadge(
                        label: 'IMDb ${(show.voteAverage ?? 0.0).toStringAsFixed(1)}',
                        color: DashboardTheme.signalRed,
                      ),
                    ],
                  ),
                  SizedBox(height: s(18)),
                  // Title
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: s(1250)),
                    child: Text(
                      show.name?.toUpperCase() ?? 'TV SHOW',
                      style: DashboardTheme.heroTitle(context),
                    ),
                  ),
                  SizedBox(height: s(14)),
                  // Meta row
                  Row(
                    children: [
                      Text(
                        _formatDate(show.firstAirDate),
                        style: DashboardTheme.heroMeta(context),
                      ),
                      SizedBox(width: s(18)),
                      Text(
                        '${show.numberOfSeasons ?? 0} Seasons',
                        style: DashboardTheme.heroMeta(context),
                      ),
                    ],
                  ),
                  SizedBox(height: s(20)),
                  // Overview
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: s(880)),
                    child: Text(
                      show.overview ?? '',
                      style: DashboardTheme.heroMeta(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(height: s(36)),
                  // Primary Action Buttons
                  Row(
                    children: [
                      _buildUpNextButton(s),
                      SizedBox(width: s(20)),
                      _ActionBtn(
                        label: '',
                        icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                        isPrimary: false,
                        onTap: _toggleFavorite,
                        s: s,
                      ),
                    ],
                  ),
                  SizedBox(height: s(64)),
                  // Seasons List
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
                  // Episodes List
                  _SectionHeader(title: 'EPISODES', s: s),
                  SizedBox(height: s(24)),
                  if (episodes.isEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: s(48)),
                        child: Text(
                          'Loading episodes...',
                          style: TextStyle(color: Colors.white54, fontSize: s(20)),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ...episodes.map((ep) {
                          final history = _seasonHistory?.firstWhere(
                            (h) => h['episode_num'] == ep.episodeNumber,
                            orElse: () => {},
                          );
                          final elapsed = (history != null && history.isNotEmpty) ? history['elapsed_ms'] as int? ?? 0 : 0;
                          final duration = (history != null && history.isNotEmpty) ? history['duration_ms'] as int? ?? 0 : 0;
                          final progress = duration > 0 ? (elapsed / duration).clamp(0.0, 1.0) : 0.0;
                          final isWatched = (history != null && history['is_completed'] == true) || progress > 0.95;

                          return Padding(
                            padding: EdgeInsets.only(bottom: s(16)),
                            child: LongPressFocus(
                              onLongPress: () => _showEpisodeContextMenu(ep, isWatched),
                              onTap: () => _handlePlay(ep.seasonNumber, ep.episodeNumber, ep.id, ep.name, elapsed: elapsed),
                              onFocusChange: (focused) {
                                if (focused) setState(() {});
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: focused ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(s(16)),
                                      border: Border.all(
                                        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.1),
                                        width: s(1.5),
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.all(s(16)),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(s(8)),
                                                child: Container(
                                                  width: s(180),
                                                  height: s(100),
                                                  color: Colors.white.withValues(alpha: 0.05),
                                                  child: ep.stillPath != null
                                                      ? CachedNetworkImage(
                                                          imageUrl: '$tmdbImageBaseUrl/w300${ep.stillPath}',
                                                          fit: BoxFit.cover,
                                                        )
                                                      : Icon(Icons.tv, color: Colors.white24, size: s(32)),
                                                ),
                                              ),
                                              SizedBox(width: s(24)),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '${ep.episodeNumber}. ${ep.name ?? "Episode ${ep.episodeNumber}"}',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontSize: s(22),
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        AnimatedSwitcher(
                                                          duration: const Duration(milliseconds: 400),
                                                          transitionBuilder: (child, animation) => ScaleTransition(
                                                            scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
                                                            child: child,
                                                          ),
                                                          child: isWatched
                                                              ? Padding(
                                                                  key: const ValueKey('watched'),
                                                                  padding: EdgeInsets.only(left: s(8)),
                                                                  child: Icon(Icons.check_circle, color: DashboardTheme.signalRed, size: s(24)),
                                                                )
                                                              : const SizedBox.shrink(key: ValueKey('not_watched')),
                                                        ),
                                                      ],
                                                    ),
                                                    if (ep.airDate != null || ep.voteAverage != null) ...[
                                                      SizedBox(height: s(6)),
                                                      Row(
                                                        children: [
                                                          if (ep.airDate != null && ep.airDate!.isNotEmpty) ...[
                                                            Icon(Icons.calendar_month, color: Colors.white54, size: s(16)),
                                                            SizedBox(width: s(6)),
                                                            Text(
                                                              ep.airDate!,
                                                              style: TextStyle(color: Colors.white54, fontSize: s(16)),
                                                            ),
                                                          ],
                                                          if ((ep.airDate != null && ep.airDate!.isNotEmpty) &&
                                                              (ep.voteAverage != null && ep.voteAverage! > 0))
                                                            SizedBox(width: s(24)),
                                                          if (ep.voteAverage != null && ep.voteAverage! > 0) ...[
                                                            Icon(Icons.star, color: Colors.orangeAccent, size: s(16)),
                                                            SizedBox(width: s(6)),
                                                            Text(
                                                              ep.voteAverage!.toStringAsFixed(1),
                                                              style: TextStyle(color: Colors.white54, fontSize: s(16)),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                    if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                                                      SizedBox(height: s(8)),
                                                      Text(
                                                        ep.overview!,
                                                        style: TextStyle(
                                                          color: Colors.white.withValues(alpha: 0.6),
                                                          fontSize: s(16),
                                                          height: 1.4,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                    if (progress > 0 && !isWatched) ...[
                                                      SizedBox(height: s(12)),
                                                      Stack(
                                                        children: [
                                                          Container(
                                                            height: s(4),
                                                            width: s(200),
                                                            decoration: BoxDecoration(
                                                              color: Colors.white.withValues(alpha: 0.1),
                                                              borderRadius: BorderRadius.circular(s(2)),
                                                            ),
                                                          ),
                                                          Container(
                                                            height: s(4),
                                                            width: s(200 * progress),
                                                            decoration: BoxDecoration(
                                                              color: DashboardTheme.signalRed,
                                                              borderRadius: BorderRadius.circular(s(2)),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              if (focused)
                                                Padding(
                                                  padding: EdgeInsets.only(left: s(16)),
                                                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: s(48)),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (_recentlyCompletedIds.contains(ep.id))
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(s(16)),
                                              child: _EpisodeShine(s: s),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                        if (_bannerAd != null) ...[
                          SizedBox(height: s(64)),
                          NativeAdBanner(ad: _bannerAd!),
                        ],
                      ],
                    ),
                  SizedBox(height: s(64)),
                  // Cast List
                  if (_credits != null && _credits!.cast.isNotEmpty) ...[
                    _SectionHeader(title: 'CAST', s: s),
                    SizedBox(height: s(24)),
                    SizedBox(
                      height: s(250),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _credits!.cast.length,
                        itemBuilder: (context, index) {
                          final actor = _credits!.cast[index];
                          return Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => ActorScreen(personId: actor.id)),
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
                                      MaterialPageRoute(builder: (context) => ActorScreen(personId: actor.id)),
                                    );
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: s(160),
                                    margin: EdgeInsets.only(right: s(32)),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(s(16)),
                                      color: focused ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                      border: Border.all(
                                        color: focused ? Colors.white : Colors.transparent,
                                        width: s(2),
                                      ),
                                    ),
                                    padding: EdgeInsets.all(s(8)),
                                    child: Column(
                                      children: [
                                        ClipOval(
                                          child: Container(
                                            width: s(110),
                                            height: s(110),
                                            color: Colors.white10,
                                            child: actor.profilePath != null
                                                ? CachedNetworkImage(
                                                    imageUrl: '$tmdbImageBaseUrl/w185${actor.profilePath}',
                                                    fit: BoxFit.cover,
                                                  )
                                                : Icon(Icons.person, color: Colors.white24, size: s(48)),
                                          ),
                                        ),
                                        SizedBox(height: s(12)),
                                        Text(
                                          actor.name,
                                          style: TextStyle(
                                            color: focused ? Colors.white : Colors.white70,
                                            fontSize: s(16),
                                            fontWeight: FontWeight.bold,
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
                  // Recommendations
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
                            quality: QualityUtils.getQualityBadgeSync(
                              mediaId: rec.id,
                              releaseDate: rec.firstAirDate,
                              isMovie: false,
                            ),
                            mediaId: rec.id,
                            isMovie: false,
                            releaseDate: rec.firstAirDate,
                          );
                        },
                      ),
                    ),
                  ],
                ],
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
      style: DashboardTheme.sectionTitle(context).copyWith(fontSize: s(20)),
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
  double _scaleFactor = 1.0;

  void _handleTap() {
    setState(() => _scaleFactor = 1.08);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scaleFactor = 1.0);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final hasLabel = widget.label.trim().isNotEmpty;
    return AnimatedScale(
      scale: _scaleFactor,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutBack,
      child: Focus(
        autofocus: widget.autofocus,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
                  gradient: widget.isPrimary && !focused ? DashboardTheme.accentGradient : null,
                  color: widget.isPrimary
                      ? (focused ? Colors.white : null)
                      : (focused ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(widget.s(12)),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white.withValues(alpha: 0.15),
                    width: widget.s(focused ? 1.5 : 1),
                  ),
                  boxShadow: focused ? [
                    BoxShadow(
                      color: (widget.isPrimary ? DashboardTheme.signalRed : Colors.black).withValues(alpha: 0.3),
                      blurRadius: widget.s(15),
                      spreadRadius: widget.s(2),
                    )
                  ] : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.s(12)),
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.s(hasLabel ? 32 : 20),
                          vertical: widget.s(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.icon, 
                              color: widget.isPrimary ? (focused ? Colors.black : Colors.white) : Colors.white,
                              size: widget.s(28),
                            ),
                            if (hasLabel) ...[
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
                            color: Colors.white.withValues(alpha: 0.2),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: widget.progress!.clamp(0.0, 1.0),
                              child: Container(color: focused ? Colors.black : DashboardTheme.signalRed),
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
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
            color: _isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(s(12)),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.15),
              width: s(1.5),
            ),
            boxShadow: _isFocused
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2)]
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
      backgroundColor: DashboardTheme.surfaceRaised,
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
                color: Colors.white.withValues(alpha: 0.5),
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

  void _showSeasonContextMenu() {
    final s = widget.s;
    final parent = context.findAncestorStateOfType<_TvDetailScreenState>();
    if (parent == null) return;

    ContextMenuDialog.show(
      context: context,
      title: 'Season ${widget.num} Actions',
      s: s,
      items: [
        ContextMenuItem(
          label: 'Mark Season as Completed',
          icon: Icons.done_all,
          onTap: () async {
            if (parent._show == null) return;
            final episodes = parent._seasons?[widget.num]?.episodes;
            if (episodes == null) return;
            await parent._historyService.markSeasonAsComplete(
              item: parent._show!,
              season: widget.num,
              episodes: episodes,
            );
            parent._load();
          },
        ),
        ContextMenuItem(
          label: 'Remove Season from History',
          icon: Icons.delete_sweep_outlined,
          color: Colors.redAccent,
          onTap: () async {
            if (parent._show == null) return;
            await parent._historyService.removeSeasonFromHistory(
              id: parent._show!.id,
              season: widget.num,
            );
            parent._load();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return LongPressFocus(
      onLongPress: _showSeasonContextMenu,
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.only(bottom: s(8)),
          padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(16)),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : (widget.selected ? DashboardTheme.signalRed.withValues(alpha: 0.2) : Colors.transparent),
            borderRadius: BorderRadius.circular(s(8)),
            border: Border.all(
              color: _isFocused ? Colors.white : (widget.selected ? DashboardTheme.signalRed : Colors.transparent),
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
                  color: _isFocused ? Colors.black : DashboardTheme.signalRed,
                  size: s(20),
                ),
            ],
          ),
      ),
    );
  }
}

class _EpisodeShine extends StatefulWidget {
  final double Function(double) s;
  const _EpisodeShine({required this.s});

  @override
  State<_EpisodeShine> createState() => _EpisodeShineState();
}

class _EpisodeShineState extends State<_EpisodeShine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ShinePainter(
            progress: _controller.value,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ShinePainter extends CustomPainter {
  final double progress;

  _ShinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // A diagonal sweep animation
    final paint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1.5, -1.5),
        end: const Alignment(1.5, 1.5),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.1),
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: [
          (progress - 0.4).clamp(0.0, 1.0),
          (progress - 0.1).clamp(0.0, 1.0),
          progress.clamp(0.0, 1.0),
          (progress + 0.1).clamp(0.0, 1.0),
          (progress + 0.4).clamp(0.0, 1.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShinePainter oldDelegate) => oldDelegate.progress != progress;
}
