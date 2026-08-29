import 'dart:async';

import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/constants.dart';
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
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/widgets/native_ad_banner.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
          });
          _checkFavorite();
          _loadQuality();
        }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Resume Playback?', style: TextStyle(color: Colors.white)),
          content: Text('Do you want to resume from ${_movieHistory!.toString().split('.').first}?', style: const TextStyle(color: Colors.white70)),
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
    }
  }

  Future<void> _loadQuality() async {
    if (_movie == null) return;
    final q = await QualityUtils.getQualityBadgeAsync(
      mediaId: _movie!.id,
      releaseDate: _movie!.releaseDate,
      isMovie: true,
    );
    if (mounted) setState(() => _qualityBadge = q);
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
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_movie == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F14),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final m = _movie!;
    final backdropUrl = m.backdropPath != null && m.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${m.backdropPath}'
        : null;

    double s(double v) => (v * MediaQuery.of(context).size.width) / 1920;

    return Scaffold(
      backgroundColor: const Color(0xFF000000), 
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
          // Accent Overlay Gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    const Color(0xFF7F1D1D).withValues(alpha: 0.6), 
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
                  colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.8)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   if (m.posterPath != null && m.posterPath!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: '$tmdbImageBaseUrl/w500${m.posterPath}',
                        width: 200,
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(vertical: s(60)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(s(24)),
                            child: BackdropFilter(
                              filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.35), BlendMode.darken),
                              child: Container(
                                padding: EdgeInsets.all(s(40)),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(s(24)),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: s(1.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Focus(
                                      descendantsAreFocusable: false,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.title?.toUpperCase() ?? 'MOVIE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: s(100),
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: s(-2),
                                              height: 0.9,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black.withValues(alpha: 0.5),
                                                  offset: Offset(0, s(4)),
                                                  blurRadius: s(10),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: s(24)),
                                          Row(
                                            children: [
                                              if (_qualityBadge != null) ...[
                                                Container(
                                                  padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                                                  decoration: BoxDecoration(
                                                    color: _qualityBadge == 'CAM' ? Colors.red.withValues(alpha: 0.9) : 
                                                           _qualityBadge == 'SOON' ? Colors.amber.withValues(alpha: 0.9) :
                                                           Colors.white.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(s(6)),
                                                    border: Border.all(
                                                      color: _qualityBadge == 'CAM' ? Colors.redAccent.withValues(alpha: 0.5) : 
                                                             _qualityBadge == 'SOON' ? Colors.amberAccent.withValues(alpha: 0.5) :
                                                             Colors.white24,
                                                      width: s(1.5)
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _qualityBadge!.toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: s(18),
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(width: s(24)),
                                              ],
                                               Container(
                                                 padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                                                 decoration: BoxDecoration(
                                                   color: const Color(0xFFEC1D24),
                                                   borderRadius: BorderRadius.circular(s(4)),
                                                 ),
                                                 child: Text(
                                                   'IMDb ${(m.voteAverage ?? 0.0).toStringAsFixed(1)}',
                                                   style: TextStyle(
                                                     color: Colors.white,
                                                     fontSize: s(18),
                                                     fontWeight: FontWeight.bold,
                                                   ),
                                                 ),
                                               ),
                                               if (_isWatched) ...[
                                                 SizedBox(width: s(24)),
                                                 Container(
                                                   padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                                                   decoration: BoxDecoration(
                                                     color: Colors.green.withValues(alpha: 0.15),
                                                     borderRadius: BorderRadius.circular(s(6)),
                                                     border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: s(1.5)),
                                                     boxShadow: [
                                                       BoxShadow(
                                                         color: Colors.green.withValues(alpha: 0.1),
                                                         blurRadius: s(8),
                                                         spreadRadius: s(2),
                                                       ),
                                                     ],
                                                   ),
                                                   child: Row(
                                                     mainAxisSize: MainAxisSize.min,
                                                     children: [
                                                       Icon(Icons.check_circle, color: Colors.green, size: s(18)),
                                                       SizedBox(width: s(8)),
                                                       Text(
                                                         'WATCHED',
                                                         style: TextStyle(
                                                           color: Colors.green,
                                                           fontSize: s(16),
                                                           fontWeight: FontWeight.bold,
                                                           letterSpacing: s(1),
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ],
                                              SizedBox(width: s(24)),
                                              Text(
                                                _formatDate(m.releaseDate),
                                                style: TextStyle(color: Colors.white70, fontSize: s(20)),
                                              ),
                                              if (m.runtime != null) ...[
                                                SizedBox(width: s(24)),
                                                Text(
                                                  '${m.runtime} m',
                                                  style: TextStyle(color: Colors.white70, fontSize: s(20)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          SizedBox(height: s(32)),
                                          SizedBox(
                                            width: s(850),
                                            child: Text(
                                              m.overview ?? '',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontSize: s(22),
                                                fontWeight: FontWeight.w400,
                                                height: 1.6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: s(48)),
                                    Row(
                                      children: [
                                        if (_isReleased) ...[
                                          _ActionBtn(
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
                                          SizedBox(width: s(24)),
                                        ],
                                        _ActionBtn(
                                          label: _isFavorite ? 'FAVORITED' : 'FAVORITE',
                                          icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                                          isPrimary: false,
                                          onTap: _toggleFavorite,
                                          s: s,
                                          autofocus: !_isReleased,
                                        ),
                                        SizedBox(width: s(24)),
                                        _ActionBtn(
                                          label: _isWatched ? 'WATCHED' : 'MARK WATCHED',
                                          icon: _isWatched ? Icons.check_circle : Icons.check_circle_outline,
                                          isPrimary: false,
                                          onTap: () => _showAddWatchMenu(s),
                                          onLongPress: () => _showWatchedLongPressMenu(s),
                                          s: s,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_credits != null && _credits!.cast.isNotEmpty) ...[
                             SizedBox(height: s(64)),
                             _SectionHeader(title: 'CAST', s: s),
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
                             _SectionHeader(title: 'PART OF ${_collection!.name?.toUpperCase() ?? 'COLLECTION'}', s: s),
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
                                     title: rec.title ?? '',
                                     onTap: () {
                                       Navigator.of(context).pushReplacement(
                                         MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: rec.id)),
                                       );
                                     },
                                     quality: QualityUtils.getQualityBadgeSync(
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
  final VoidCallback? onLongPress;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    required this.s,
    this.autofocus = false,
    this.progress,
    this.onLongPress,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  double _scale = 1.0;
  Timer? _longPressTimer;
  bool _isLongPress = false;

  void _handleTap() {
    setState(() => _scale = 1.08);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scale = 1.0);
    });
    widget.onTap();
  }

  void _handleKeyDown() {
    if (widget.onLongPress == null || _longPressTimer != null) return;
    _isLongPress = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      _isLongPress = true;
      HapticFeedback.mediumImpact();
      widget.onLongPress?.call();
    });
  }

  void _handleKeyUp() {
    final wasLongPress = _isLongPress;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (!wasLongPress) {
      _handleTap();
    }
    _isLongPress = false;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if (TvKeys.isSelect(event.logicalKey)) {
          if (event is KeyDownEvent) {
            _handleKeyDown();
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _handleKeyUp();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return GestureDetector(
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.s(8)),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  transform: Matrix4.identity()..scaleByDouble(focused ? 1.05 : 1.0, focused ? 1.05 : 1.0, 1.0, 1.0),
                  padding: EdgeInsets.symmetric(horizontal: widget.s(40), vertical: widget.s(16)),
                  decoration: BoxDecoration(
                    color: widget.isPrimary 
                        ? (focused ? Colors.white : const Color(0xFFEC1D24).withValues(alpha: 0.8))
                        : (focused ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(widget.s(12)),
                    border: Border.all(
                      color: focused ? Colors.white : Colors.white.withValues(alpha: 0.15),
                      width: widget.s(1.5),
                    ),
                    boxShadow: focused ? [
                      BoxShadow(
                        color: (widget.isPrimary ? const Color(0xFFEC1D24) : Colors.white).withValues(alpha: 0.3),
                        blurRadius: widget.s(15),
                        spreadRadius: widget.s(2),
                      )
                    ] : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon, 
                        color: widget.isPrimary 
                            ? (focused ? Colors.black : Colors.white)
                            : Colors.white,
                        size: widget.s(28)
                      ),
                      SizedBox(width: widget.s(12)),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.isPrimary 
                              ? (focused ? Colors.black : Colors.white)
                              : Colors.white,
                          fontSize: widget.s(20),
                          fontWeight: FontWeight.bold,
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
                      color: Colors.white.withValues(alpha: 0.2),
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
        );
      }),
    );
  }
}
