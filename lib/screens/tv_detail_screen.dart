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
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _isFavorite = false;
  String? _error;

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

      // Fetch recommendations and credits in parallel
      await Future.wait([
        _api.fetchTvRecommendations(widget.tvId).then((r) => recs = r.results).catchError((_) => recs = []),
        _api.fetchTvCredits(widget.tvId).then((c) => credits = c).catchError((_) => credits = CreditsResponse(id: widget.tvId, cast: [])),
      ]);

      if (mounted) {
        setState(() {
          _show = show;
          _seasons = {};
          if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) {
            _selectedSeason = 1;
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
    if (_seasons!.containsKey(num)) return;
    try {
      final detail = await _api.fetchSeasonDetail(widget.tvId, num);
      if (mounted) setState(() => _seasons![num] = detail);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update favorites: $e')),
      );
    }
  }

  void _playEpisode(int season, int episode) {
    if (_show == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLoaderScreen(
          tvShow: _show!,
          season: season,
          episode: episode,
        ),
      ),
    );
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
                            Row(
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
                                              color: Colors.white.withOpacity(0.8),
                                              fontSize: s(22),
                                              fontWeight: FontWeight.w400,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: s(64)),
                            // Action Buttons (Favorite/Share) - Play is handled per episode
                            Row(
                              children: [
                                _ActionBtn(
                                  label: _isFavorite ? 'FAVOURITED' : 'FAVOURITE',
                                  icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                                  isPrimary: _isFavorite,
                                  onTap: _toggleFavorite,
                                  s: s,
                                  autofocus: true,
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
                              SizedBox(
                                height: s(60),
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: show.numberOfSeasons!,
                                  itemBuilder: (context, i) {
                                    final num = i + 1;
                                    final selected = _selectedSeason == num;
                                    return Padding(
                                      padding: EdgeInsets.only(right: s(16)),
                                      child: Focus(
                                        descendantsAreFocusable: false,
                                        onKeyEvent: (node, event) {
                                          if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                          if (event.logicalKey == LogicalKeyboardKey.enter ||
                                              event.logicalKey == LogicalKeyboardKey.select) {
                                            setState(() { _selectedSeason = num; _loadSeason(num); });
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: Builder(
                                          builder: (context) {
                                            final focused = Focus.of(context).hasFocus;
                                            return GestureDetector(
                                              onTap: () { setState(() { _selectedSeason = num; _loadSeason(num); }); },
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                padding: EdgeInsets.symmetric(horizontal: s(32)),
                                                decoration: BoxDecoration(
                                                  color: selected 
                                                      ? const Color(0xFFDC2626) 
                                                      : (focused ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
                                                  borderRadius: BorderRadius.circular(s(8)),
                                                  border: Border.all(
                                                    color: focused ? Colors.white : Colors.transparent,
                                                    width: s(2),
                                                  ),
                                                  boxShadow: focused
                                                      ? [BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10)]
                                                      : [],
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    'SEASON $num',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: s(18),
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: s(1),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        ),
                                      ),
                                    );
                                  },
                                ),
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
                                          _playEpisode(ep.seasonNumber, ep.episodeNumber);
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final focused = Focus.of(context).hasFocus;
                                          return GestureDetector(
                                            onTap: () => _playEpisode(ep.seasonNumber, ep.episodeNumber),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              padding: EdgeInsets.all(s(16)),
                                              decoration: BoxDecoration(
                                                color: focused ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.02),
                                                borderRadius: BorderRadius.circular(s(16)),
                                                border: Border.all(
                                                  color: focused ? Colors.white : Colors.white.withOpacity(0.05),
                                                  width: s(2),
                                                ),
                                                boxShadow: focused
                                                    ? [BoxShadow(color: const Color(0xFFEC1D24).withOpacity(0.25), blurRadius: 16)]
                                                    : [],
                                              ),
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
                                                        Text(
                                                          'E${ep.episodeNumber} - ${ep.name ?? ""}',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: s(22),
                                                            fontWeight: focused ? FontWeight.bold : FontWeight.w600,
                                                          ),
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

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    required this.s,
    this.autofocus = false,
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
                padding: EdgeInsets.symmetric(horizontal: widget.s(32), vertical: widget.s(16)),
                decoration: BoxDecoration(
                  color: widget.isPrimary 
                      ? (focused ? Colors.white : const Color(0xFFEC1D24))
                      : (focused ? Colors.white.withOpacity(0.2) : Colors.transparent),
                  borderRadius: BorderRadius.circular(widget.s(8)),
                  border: widget.isPrimary 
                      ? Border.all(color: Colors.white, width: widget.s(focused ? 4 : 0))
                      : Border.all(color: Colors.white, width: widget.s(1)),
                  boxShadow: (widget.isPrimary && focused) 
                      ? [BoxShadow(color: Colors.white.withOpacity(0.4), blurRadius: 15)]
                      : [],
                ),
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
            );
          }
        ),
      ),
    );
  }
}
