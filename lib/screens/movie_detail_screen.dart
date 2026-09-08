import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/screens/video_loader_screen.dart';
import 'package:reelriot_tv/screens/actor_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:reelriot_tv/widgets/add_watch_menu.dart';
import 'package:reelriot_tv/widgets/context_menu_dialog.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/services/bookmark_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/utils/auth_error_utils.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/native_ad_banner.dart';
import 'package:reelriot_tv/widgets/full_screen_status.dart';
import 'package:reelriot_tv/widgets/hero_badge.dart';
import 'package:reelriot_tv/widgets/action_button.dart';
import 'package:reelriot_tv/widgets/section_header.dart';
import '../models/ad.dart' as model;

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movieId});

  final int movieId;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final ApiService _api = ApiService();
  MovieDetail? _movie;
  List<MovieListItem>? _recommendations;
  CreditsResponse? _credits;
  final BookmarkService _bookmarkService = BookmarkService();
  bool _isFavorite = false;
  String? _error;
  Duration? _movieHistory;
  bool _isWatched = false;
  final WatchHistoryService _historyService = WatchHistoryService();
  MovieCollection? _collection;
  bool _isProcessing = false;
  model.Ad? _bannerAd;
  String? _qualityBadge;
  final ScrollController _scrollController = ScrollController();

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
      final m = await _api.fetchMovieDetail(widget.movieId);
      List<MovieListItem>? recs;
      CreditsResponse? credits;
      
      // Fetch recommendations, credits, and watch history in parallel
      await Future.wait([
        _api.fetchMovieRecommendations(widget.movieId).then((r) => recs = r.results).catchError((_) => recs = []),
        _api.fetchMovieCredits(widget.movieId).then((c) => credits = c).catchError((_) => credits = CreditsResponse(id: widget.movieId, cast: [])),
        _historyService.getWatchProgressInfo(widget.movieId, true).then((p) {
          if (p != null) {
            _movieHistory = p['elapsed'] as Duration?;
            _isWatched = p['is_finished'] as bool? ?? false;
          }
        }),
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

      // Fetch collection if it exists
      if (m.belongsToCollection != null) {
        final collectionId = m.belongsToCollection!['id'] as int;
        try {
          final col = await _api.fetchMovieCollection(collectionId);
          if (mounted) {
            setState(() => _collection = col);
          }
        } catch (e) {
          debugPrint('[MovieDetail] ⚠️ Failed to load collection: $e');
        }
      }

        if (mounted) {
          setState(() {
            _movie = m;
            _recommendations = recs;
            _credits = credits;
            _qualityBadge = QualityUtils.getQualityBadgeSync(
              mediaId: m.id,
              releaseDate: m.releaseDate,
              isMovie: true,
            );
          });
          _checkFavorite();
          _loadQuality();
          _resetScrollToTop();
        }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      await handleIfUnrecoverableAuthError(e);
    }
  }

  void _play({Duration? startPosition}) async {
    if (_movie == null) return;
    
    // Show interstitial ad before navigation
    await AdService.instance.showInterstitialAd();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLoaderScreen(
          movie: _movie!,
          startPosition: startPosition,
        ),
      ),
    ).then((_) async {
      await Future.delayed(const Duration(seconds: 2));
      _load();
    });
  }

  void _handlePlay() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      if (_movieHistory != null && _movieHistory! > Duration.zero) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: DashboardTheme.surfaceRaised,
          title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
          content: Text('Do you want to resume from ${_movieHistory!.toString().split('.').first}?', style: const TextStyle(color: Colors.white70)),
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
        _play(startPosition: _movieHistory);
      } else {
        _play(startPosition: Duration.zero);
      }
    } else {
      _play();
    }
    } finally {
      _isProcessing = false;
      if (mounted) setState(() {});
    }
  }

  bool get _isReleased {
    if (_movie?.releaseDate == null || _movie!.releaseDate!.isEmpty) return false;
    try {
      final releaseDate = DateTime.parse(_movie!.releaseDate!);
      // Allow if released today or earlier
      return releaseDate.isBefore(DateTime.now().add(const Duration(days: 1)));
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkFavorite() async {
    final isFav = await _bookmarkService.isBookmarked(widget.movieId, true);
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
      await _bookmarkService.toggleBookmark(_movie!, true);
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

  Future<void> _loadQuality() async {
    if (_movie == null) return;
    final q = await QualityUtils.getQualityBadgeAsync(
      mediaId: _movie!.id,
      releaseDate: _movie!.releaseDate,
      isMovie: true,
    );
    if (mounted && q != null && q != _qualityBadge) {
      setState(() => _qualityBadge = q);
    }
  }

  DateTime? _parseReleaseDate() {
    final raw = _movie?.releaseDate;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _addWatch({DateTime? watchedAt, bool unknownDate = false}) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to mark as watched')),
      );
      return;
    }
    if (_movie == null) return;

    try {
      await _historyService.addWatch(
        item: _movie!,
        isMovie: true,
        watchedAt: watchedAt,
        unknownDate: unknownDate,
      );
      _load(); // Refresh state
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update watched status: $e')),
        );
      }
      await handleIfUnrecoverableAuthError(e);
    }
  }

  Future<void> _unmarkWatched() async {
    if (_movie == null) return;
    await _historyService.removeFromHistory(id: _movie!.id, isMovie: true);
    _load();
  }

  void _showAddWatchMenu(double Function(double) s) {
    if (_movie == null) return;
    AddWatchMenu.show(
      context: context,
      title: _movie!.title ?? '',
      s: s,
      releaseDate: _parseReleaseDate(),
      onPick: ({watchedAt, unknownDate = false}) => _addWatch(watchedAt: watchedAt, unknownDate: unknownDate),
    );
  }

  Future<void> _showWatchHistory(double Function(double) s) async {
    if (_movie == null) return;
    final events = await _historyService.getWatchEvents(mediaId: _movie!.id, isMovie: true);
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

  void _showWatchedLongPressMenu(double Function(double) s) {
    if (_movie == null) return;
    ContextMenuDialog.show(
      context: context,
      title: _movie!.title ?? '',
      s: s,
      items: [
        ContextMenuItem(
          label: 'Add Another Watch',
          icon: Icons.add_circle_outline,
          onTap: () => _showAddWatchMenu(s),
        ),
        ContextMenuItem(
          label: 'Watch History',
          icon: Icons.history_rounded,
          onTap: () => _showWatchHistory(s),
        ),
        ContextMenuItem(
          label: 'Unmark Completely',
          icon: Icons.remove_circle_outline,
          color: Colors.redAccent,
          onTap: _unmarkWatched,
        ),
      ],
    );
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

    if (_movie == null) {
      return const FullScreenLoading();
    }

    final m = _movie!;
    final backdropUrl = m.backdropPath != null && m.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${m.backdropPath}'
        : null;

    double s(double v) => ResponsiveUtils.scale(context, v);

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
                      if (_qualityBadge != null) ...[
                        HeroBadge(
                          label: _qualityBadge!.toUpperCase(),
                          color: _qualityBadge == 'CAM'
                              ? DashboardTheme.signalRed.withValues(alpha: 0.9)
                              : _qualityBadge == 'SOON'
                                  ? DashboardTheme.warningAmber.withValues(alpha: 0.9)
                                  : Colors.white.withValues(alpha: 0.15),
                          borderColor: _qualityBadge == 'CAM'
                              ? DashboardTheme.signalRed.withValues(alpha: 0.5)
                              : _qualityBadge == 'SOON'
                                  ? DashboardTheme.warningAmber.withValues(alpha: 0.5)
                                  : Colors.white24,
                        ),
                        SizedBox(width: s(14)),
                      ],
                      HeroBadge(
                        label: 'IMDb ${(m.voteAverage ?? 0.0).toStringAsFixed(1)}',
                        color: DashboardTheme.signalRed,
                      ),
                      if (_isWatched) ...[
                        SizedBox(width: s(14)),
                        HeroBadge(
                          label: 'WATCHED',
                          icon: Icons.check_circle,
                          color: DashboardTheme.successGreen.withValues(alpha: 0.18),
                          borderColor: DashboardTheme.successGreen.withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: s(18)),
                  // Title
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: s(1250)),
                    child: Text(
                      m.title?.toUpperCase() ?? 'MOVIE',
                      style: DashboardTheme.heroTitle(context),
                    ),
                  ),
                  SizedBox(height: s(14)),
                  // Meta row
                  Row(
                    children: [
                      Text(
                        _formatDate(m.releaseDate),
                        style: DashboardTheme.heroMeta(context),
                      ),
                      if (m.runtime != null) ...[
                        SizedBox(width: s(18)),
                        Text('${m.runtime}m', style: DashboardTheme.heroMeta(context)),
                      ],
                    ],
                  ),
                  SizedBox(height: s(20)),
                  // Overview
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: s(880)),
                    child: Text(
                      m.overview ?? '',
                      style: DashboardTheme.heroMeta(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(height: s(36)),
                  // Actions
                  Row(
                    children: [
                      if (_isReleased) ...[
                        ActionButton(
                          label: _movieHistory != null && _movieHistory! > Duration.zero ? 'CONTINUE' : 'WATCH NOW',
                          icon: Icons.play_arrow,
                          isPrimary: true,
                          onTap: _handlePlay,
                          s: s,
                          autofocus: true,
                          progress: (_movieHistory != null && _movie?.id != null)
                              ? (_movieHistory!.inSeconds / 7200).clamp(0.0, 1.0)
                              : null,
                        ),
                        SizedBox(width: s(20)),
                      ],
                      ActionButton(
                        label: _isFavorite ? 'FAVORITED' : 'FAVORITE',
                        icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                        isPrimary: false,
                        onTap: _toggleFavorite,
                        s: s,
                        autofocus: !_isReleased,
                      ),
                      SizedBox(width: s(20)),
                      ActionButton(
                        label: _isWatched ? 'WATCHED' : 'MARK WATCHED',
                        icon: _isWatched ? Icons.check_circle : Icons.check_circle_outline,
                        isPrimary: false,
                        onTap: () => _showAddWatchMenu(s),
                        onLongPress: () => _showWatchedLongPressMenu(s),
                        s: s,
                      ),
                    ],
                  ),
                  if (_credits != null && _credits!.cast.isNotEmpty) ...[
                             SizedBox(height: s(64)),
                             SectionHeader(title: 'CAST', s: s),
                             SizedBox(height: s(24)),
                             SizedBox(
                               height: s(260),
                               child: ListView.builder(
                                 scrollDirection: Axis.horizontal,
                                 itemCount: _credits!.cast.length,
                                 itemBuilder: (context, index) {
                                   final actor = _credits!.cast[index];
                                   return Focus(
                                     onKeyEvent: (_, event) {
                                       if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
                                             width: s(180),
                                             margin: EdgeInsets.only(right: s(32)),
                                             decoration: BoxDecoration(
                                               borderRadius: BorderRadius.circular(s(20)),
                                               border: Border.all(
                                                 color: focused ? Colors.white : Colors.white.withValues(alpha: 0.12),
                                                 width: s(2),
                                               ),
                                               color: focused ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
                                               boxShadow: focused ? [
                                                 BoxShadow(
                                                   color: Colors.black.withValues(alpha: 0.3),
                                                   blurRadius: s(15),
                                                   spreadRadius: s(2),
                                                 )
                                               ] : [],
                                             ),
                                             padding: EdgeInsets.all(s(12)),
                                             child: Column(
                                               children: [
                                                 ClipOval(
                                                   child: actor.profilePath != null
                                                       ? CachedNetworkImage(
                                                           imageUrl: '$tmdbImageBaseUrl/w185${actor.profilePath}',
                                                           width: s(120),
                                                           height: s(120),
                                                           fit: BoxFit.cover,
                                                         )
                                                       : Container(
                                                           width: s(120),
                                                           height: s(120),
                                                           color: Colors.white12,
                                                           child: Icon(Icons.person, color: Colors.white54, size: s(48)),
                                                         ),
                                                 ),
                                                 SizedBox(height: s(16)),
                                                 Text(
                                                   actor.name,
                                                   style: TextStyle(
                                                     color: focused ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                                     fontSize: s(18),
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
                           if (_collection != null && _collection!.parts.length > 1) ...[
                             SizedBox(height: s(64)),
                             SectionHeader(title: 'PART OF ${_collection!.name?.toUpperCase() ?? 'COLLECTION'}', s: s),
                             SizedBox(height: s(24)),
                             SizedBox(
                               height: s(380),
                               child: ListView.builder(
                                 scrollDirection: Axis.horizontal,
                                 itemCount: _collection!.parts.length,
                                 itemBuilder: (context, index) {
                                   final part = _collection!.parts[index];
                                   // Skip current movie from the list if desired, but typically we show all parts
                                   return Padding(
                                     padding: EdgeInsets.only(right: s(24)),
                                     child: PosterCard(
                                       posterPath: part.posterPath,
                                       title: part.title ?? '',
                                       onTap: () {
                                         if (part.id == widget.movieId) return; // Already on this movie
                                         Navigator.of(context).pushReplacement(
                                           MaterialPageRoute(
                                             builder: (context) => MovieDetailScreen(movieId: part.id),
                                           ),
                                         );
                                       },
                                       quality: QualityUtils.getQualityBadgeSync(
                                         mediaId: part.id,
                                         releaseDate: part.releaseDate,
                                         isMovie: true,
                                       ),
                                       mediaId: part.id,
                                       isMovie: true,
                                       releaseDate: part.releaseDate,
                                     ),
                                   );
                                 },
                               ),
                             ),
                           ],
                           if (_recommendations != null && _recommendations!.isNotEmpty) ...[
                             SizedBox(height: s(64)),
                             SectionHeader(title: 'MORE LIKE THIS', s: s),
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
                                     title: rec.title ?? '',
                                     onTap: () {
                                       Navigator.of(context).pushReplacement(
                                         MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: rec.id)),
                                       );
                                     },
                                     quality: QualityUtils.getQualityBadgeSync(
                                       mediaId: rec.id,
                                       releaseDate: rec.releaseDate,
                                       isMovie: true,
                                     ),
                                     mediaId: rec.id,
                                     isMovie: true,
                                     releaseDate: rec.releaseDate,
                                   );
                                 },
                               ),
                             ),
                           ],
                  if (_bannerAd != null) ...[
                    SizedBox(height: s(64)),
                    NativeAdBanner(ad: _bannerAd!),
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

