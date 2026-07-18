import 'dart:convert';
import 'package:reelriot_tv/env.dart';
import 'package:reelriot_tv/screens/sports_game_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/screens/player_screen.dart';
import 'package:reelriot_tv/services/ad_service.dart';

// ---------------------------------------------------------------------------
// ESPN league config
// ---------------------------------------------------------------------------

class _League {
  final String name;
  final String sport; // ESPN path segment (e.g. basketball)
  final String league; // ESPN path segment (e.g. nba)
  final IconData icon;
  final Color color;
  const _League({
    required this.name,
    required this.sport,
    required this.league,
    required this.icon,
    required this.color,
  });
}

const _leagues = [
  // ── Basketball ─────────────────────────────────────────────────────────
  _League(
    name: 'NBA',
    sport: 'basketball',
    league: 'nba',
    icon: Icons.sports_basketball,
    color: Color(0xFFF97316),
  ),
  _League(
    name: 'NBA Summer League',
    sport: 'basketball',
    league: 'nba-summer',
    icon: Icons.sports_basketball,
    color: Color(0xFFF97316),
  ),
  _League(
    name: 'NCAAB (Men)',
    sport: 'basketball',
    league: 'mens-college-basketball',
    icon: Icons.sports_basketball,
    color: Color(0xFFF59E0B),
  ),
  _League(
    name: 'NCAAW (Women)',
    sport: 'basketball',
    league: 'womens-college-basketball',
    icon: Icons.sports_basketball,
    color: Color(0xFFEC4899),
  ),
  _League(
    name: 'WNBA',
    sport: 'basketball',
    league: 'wnba',
    icon: Icons.sports_basketball,
    color: Color(0xFFE11D48),
  ),
  // ── American Football ───────────────────────────────────────────────────
  _League(
    name: 'NFL',
    sport: 'football',
    league: 'nfl',
    icon: Icons.sports_football,
    color: Color(0xFF8B5CF6),
  ),
  _League(
    name: 'College Football',
    sport: 'football',
    league: 'college-football',
    icon: Icons.sports_football,
    color: Color(0xFF7C3AED),
  ),
  _League(
    name: 'CFL',
    sport: 'football',
    league: 'cfl',
    icon: Icons.sports_football,
    color: Color(0xFFA78BFA),
  ),
  // ── Baseball ────────────────────────────────────────────────────────────
  _League(
    name: 'MLB',
    sport: 'baseball',
    league: 'mlb',
    icon: Icons.sports_baseball,
    color: Color(0xFF3B82F6),
  ),
  // ── Hockey ──────────────────────────────────────────────────────────────
  _League(
    name: 'NHL',
    sport: 'hockey',
    league: 'nhl',
    icon: Icons.sports_hockey,
    color: Color(0xFF06B6D4),
  ),
  // ── Soccer — International ────────────────────────────────────────────────
  _League(
    name: 'World Cup',
    sport: 'soccer',
    league: 'fifa.world',
    icon: Icons.sports_soccer,
    color: Color(0xFFEAB308), // Gold/Yellow
  ),
  // ── Soccer — Club Leagues ────────────────────────────────────────────────
  _League(
    name: 'Premier League',
    sport: 'soccer',
    league: 'eng.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF22C55E),
  ),
  _League(
    name: 'La Liga',
    sport: 'soccer',
    league: 'esp.1',
    icon: Icons.sports_soccer,
    color: Color(0xFFEF4444),
  ),
  _League(
    name: 'Bundesliga',
    sport: 'soccer',
    league: 'ger.1',
    icon: Icons.sports_soccer,
    color: Color(0xFFD97706),
  ),
  _League(
    name: 'Serie A',
    sport: 'soccer',
    league: 'ita.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF10B981),
  ),
  _League(
    name: 'Ligue 1',
    sport: 'soccer',
    league: 'fra.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF0EA5E9),
  ),
  _League(
    name: 'Eredivisie',
    sport: 'soccer',
    league: 'ned.1',
    icon: Icons.sports_soccer,
    color: Color(0xFFFF6B00),
  ),
  _League(
    name: 'Primeira Liga',
    sport: 'soccer',
    league: 'por.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF16A34A),
  ),
  _League(
    name: 'Champions League',
    sport: 'soccer',
    league: 'uefa.champions',
    icon: Icons.sports_soccer,
    color: Color(0xFF6366F1),
  ),
  _League(
    name: 'Europa League',
    sport: 'soccer',
    league: 'uefa.europa',
    icon: Icons.sports_soccer,
    color: Color(0xFFF97316),
  ),
  _League(
    name: 'Conference League',
    sport: 'soccer',
    league: 'uefa.europa.conf',
    icon: Icons.sports_soccer,
    color: Color(0xFF22D3EE),
  ),
  _League(
    name: 'MLS',
    sport: 'soccer',
    league: 'usa.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF38BDF8),
  ),
  _League(
    name: 'Liga MX',
    sport: 'soccer',
    league: 'mex.1',
    icon: Icons.sports_soccer,
    color: Color(0xFF84CC16),
  ),
  // ── Soccer — International / FIFA ────────────────────────────────────────
  _League(
    name: 'FIFA World Cup',
    sport: 'soccer',
    league: 'fifa.world',
    icon: Icons.emoji_events,
    color: Color(0xFFFFD700),
  ),
  _League(
    name: 'Club World Cup',
    sport: 'soccer',
    league: 'fifa.cwc',
    icon: Icons.emoji_events,
    color: Color(0xFFE5C100),
  ),
  _League(
    name: 'Int\'l Friendlies',
    sport: 'soccer',
    league: 'fifa.friendly',
    icon: Icons.sports_soccer,
    color: Color(0xFF9CA3AF),
  ),
  _League(
    name: 'WC Qual. CONCACAF',
    sport: 'soccer',
    league: 'fifa.worldq.concacaf',
    icon: Icons.sports_soccer,
    color: Color(0xFF34D399),
  ),
  _League(
    name: 'WC Qual. CONMEBOL',
    sport: 'soccer',
    league: 'fifa.worldq.conmebol',
    icon: Icons.sports_soccer,
    color: Color(0xFF60A5FA),
  ),
  _League(
    name: 'WC Qual. UEFA',
    sport: 'soccer',
    league: 'fifa.worldq.uefa',
    icon: Icons.sports_soccer,
    color: Color(0xFF818CF8),
  ),
  // ── Soccer — UEFA & Confederation Tournaments ─────────────────────────────
  _League(
    name: 'UEFA Euro',
    sport: 'soccer',
    league: 'uefa.euro',
    icon: Icons.emoji_events,
    color: Color(0xFF3B82F6),
  ),
  _League(
    name: 'Euro Qualifiers',
    sport: 'soccer',
    league: 'uefa.euroq',
    icon: Icons.sports_soccer,
    color: Color(0xFF60A5FA),
  ),
  _League(
    name: 'UEFA Nations League',
    sport: 'soccer',
    league: 'uefa.nations',
    icon: Icons.sports_soccer,
    color: Color(0xFF2563EB),
  ),
  _League(
    name: 'CONCACAF Gold Cup',
    sport: 'soccer',
    league: 'concacaf.gold',
    icon: Icons.emoji_events,
    color: Color(0xFF10B981),
  ),
  _League(
    name: 'CONCACAF Nations',
    sport: 'soccer',
    league: 'concacaf.nations.league',
    icon: Icons.sports_soccer,
    color: Color(0xFF059669),
  ),
  _League(
    name: 'Copa América',
    sport: 'soccer',
    league: 'conmebol.america',
    icon: Icons.emoji_events,
    color: Color(0xFFF59E0B),
  ),
  _League(
    name: 'Copa Libertadores',
    sport: 'soccer',
    league: 'conmebol.libertadores',
    icon: Icons.sports_soccer,
    color: Color(0xFFD97706),
  ),
  // ── Racing ──────────────────────────────────────────────────────────────
  _League(
    name: 'Formula 1',
    sport: 'racing',
    league: 'f1',
    icon: Icons.speed,
    color: Color(0xFFDC2626),
  ),
  _League(
    name: 'NASCAR Cup',
    sport: 'racing',
    league: 'nascar-premier',
    icon: Icons.speed,
    color: Color(0xFF78716C),
  ),
  _League(
    name: 'IndyCar',
    sport: 'racing',
    league: 'irl',
    icon: Icons.speed,
    color: Color(0xFF0284C7),
  ),
  // ── Tennis ──────────────────────────────────────────────────────────────
  _League(
    name: 'Tennis (ATP)',
    sport: 'tennis',
    league: 'atp',
    icon: Icons.sports_tennis,
    color: Color(0xFFFBBF24),
  ),
  _League(
    name: 'Tennis (WTA)',
    sport: 'tennis',
    league: 'wta',
    icon: Icons.sports_tennis,
    color: Color(0xFFF472B6),
  ),
  // ── Golf ────────────────────────────────────────────────────────────────
  _League(
    name: 'PGA Tour',
    sport: 'golf',
    league: 'pga',
    icon: Icons.sports_golf,
    color: Color(0xFF4ADE80),
  ),
  _League(
    name: 'LIV Golf',
    sport: 'golf',
    league: 'liv',
    icon: Icons.sports_golf,
    color: Color(0xFF86EFAC),
  ),
  // ── Rugby ───────────────────────────────────────────────────────────────
  _League(
    name: 'Rugby Union',
    sport: 'rugby-union',
    league: 'intl',
    icon: Icons.sports_rugby,
    color: Color(0xFF6EE7B7),
  ),
  // ── MMA / Combat ────────────────────────────────────────────────────────
  _League(
    name: 'UFC / MMA',
    sport: 'mma',
    league: 'ufc',
    icon: Icons.sports_mma,
    color: Color(0xFFDC2626),
  ),
];

// ---------------------------------------------------------------------------
// ESPN models (minimal, same shape as caffeine mobile)
// ---------------------------------------------------------------------------

class _EspnGame {
  final String id;
  final String name;
  final String shortName;
  final bool isLive;
  final bool isCompleted;
  final String? scoreLine;
  final String? statusText;
  final String? startTimeLocal;
  final String? awayTeam;
  final String? homeTeam;
  final String? awayLogo;
  final String? homeLogo;
  final String? awayScore;
  final String? homeScore;
  final String? displayClock;
  final int? period;
  final DateTime? startTimeUtc;
  final String? sport;
  final String? league;
  final String? videoUrl;
  final String? referrer;
  final String? eventTitle;
  final List<dynamic>? sources;
  final bool isManualEnded;

  const _EspnGame({
    required this.id,
    required this.name,
    required this.shortName,
    required this.isLive,
    required this.isCompleted,
    this.scoreLine,
    this.statusText,
    this.startTimeLocal,
    this.awayTeam,
    this.homeTeam,
    this.awayLogo,
    this.homeLogo,
    this.awayScore,
    this.homeScore,
    this.displayClock,
    this.period,
    this.startTimeUtc,
    this.sport,
    this.league,
    this.videoUrl,
    this.referrer,
    this.eventTitle,
    this.sources,
    this.isManualEnded = false,
  });

  _EspnGame copyWith({
    String? videoUrl,
    String? referrer,
    String? eventTitle,
    List<dynamic>? sources,
    bool? isManualEnded,
  }) {
    return _EspnGame(
      id: id,
      name: name,
      shortName: shortName,
      isLive: isLive,
      isCompleted: isCompleted,
      scoreLine: scoreLine,
      statusText: statusText,
      startTimeLocal: startTimeLocal,
      awayTeam: awayTeam,
      homeTeam: homeTeam,
      awayLogo: awayLogo,
      homeLogo: homeLogo,
      awayScore: awayScore,
      homeScore: homeScore,
      displayClock: displayClock,
      period: period,
      startTimeUtc: startTimeUtc,
      sport: sport,
      league: league,
      videoUrl: videoUrl ?? this.videoUrl,
      referrer: referrer ?? this.referrer,
      eventTitle: eventTitle ?? this.eventTitle,
      sources: sources ?? this.sources,
      isManualEnded: isManualEnded ?? this.isManualEnded,
    );
  }

  static String? _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    final utc = DateTime.tryParse(dateStr);
    if (utc == null) return null;
    final local = utc.toLocal();
    final h = local.hour;
    final m = local.minute;
    final am = h < 12;
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} ${am ? 'AM' : 'PM'}';
  }

  factory _EspnGame.fromJson(
    Map<String, dynamic> json, {
    String? sport,
    String? league,
  }) {
    final comps = json['competitions'] as List<dynamic>? ?? [];

    // Improved selection for UFC/MMA: Find the active fight or default to the Main Event
    final isMma =
        (sport?.toLowerCase() == 'mma' || league?.toLowerCase() == 'ufc');
    Map<String, dynamic>? comp;
    if (comps.isNotEmpty) {
      if (isMma) {
        // 1. Try to find the currently active fight ('in' status)
        comp =
            comps.firstWhere(
                  (c) => c is Map && c['status']?['type']?['state'] == 'in',
                  orElse: () => null,
                )
                as Map<String, dynamic>?;

        // 2. If no active fight, try to find the next upcoming fight ('pre' status)
        comp ??=
            comps.firstWhere(
                  (c) => c is Map && c['status']?['type']?['state'] == 'pre',
                  orElse: () => null,
                )
                as Map<String, dynamic>?;

        // 3. Fallback to the Main Event (last)
        comp ??= comps.last as Map<String, dynamic>?;
      } else {
        comp = comps.first as Map<String, dynamic>?;
      }
    }
    comp ??= <String, dynamic>{};
    final compets = comp['competitors'] as List<dynamic>? ?? [];

    Map<String, dynamic>? away, home;
    for (final c in compets) {
      if (c is Map<String, dynamic>) {
        if (c['homeAway'] == 'away') away = c;
        if (c['homeAway'] == 'home') home = c;
      }
    }

    // MMA/UFC Fallback: If no explicit home/away, use positional indices
    if (away == null && home == null && compets.isNotEmpty) {
      away = compets[0] as Map<String, dynamic>?;
      if (compets.length > 1) {
        home = compets[1] as Map<String, dynamic>?;
      }
    }

    String? teamName(Map<String, dynamic>? c) {
      final team = c?['team'] as Map<String, dynamic>?;
      final athlete = c?['athlete'] as Map<String, dynamic>?;
      return team?['displayName']?.toString() ??
          athlete?['displayName']?.toString();
    }

    String? teamLogo(Map<String, dynamic>? c) {
      final team = c?['team'] as Map<String, dynamic>?;
      final athlete = c?['athlete'] as Map<String, dynamic>?;
      return team?['logo']?.toString() ??
          team?['logos']?[0]?['href']?.toString() ??
          athlete?['headshot']?.toString() ??
          athlete?['flag']?.toString();
    }

    String? teamScore(Map<String, dynamic>? c) => c?['score']?.toString();

    final statusJson = comp['status'] as Map<String, dynamic>?;
    final statusType = statusJson?['type'] as Map<String, dynamic>?;
    final state = statusType?['state']?.toString() ?? 'pre';
    final isLive = state == 'in';
    // For MMA, only mark the event as completed if EVERY competition is finished
    final isCompleted = isMma
        ? comps.every((c) => (c as Map)['status']?['type']?['state'] == 'post')
        : state == 'post';
    final awayS = isMma ? null : teamScore(away);
    final homeS = isMma ? null : teamScore(home);
    final scoreLine = (awayS != null && homeS != null)
        ? '$awayS  -  $homeS'
        : null;

    return _EspnGame(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName: json['shortName']?.toString() ?? '',
      isLive: isLive,
      isCompleted: isCompleted,
      scoreLine: isLive || isCompleted ? scoreLine : null,
      statusText:
          statusJson?['shortDetail']?.toString() ??
          statusJson?['detail']?.toString(),
      startTimeLocal: _formatTime(json['date']?.toString()),
      awayTeam: teamName(away),
      homeTeam: teamName(home),
      awayLogo: teamLogo(away),
      homeLogo: teamLogo(home),
      awayScore: awayS,
      homeScore: homeS,
      displayClock: statusJson?['displayClock']?.toString(),
      period: statusJson?['period'] is int
          ? statusJson!['period']
          : (int.tryParse(statusJson?['period']?.toString() ?? '')),
      startTimeUtc: DateTime.tryParse(json['date']?.toString() ?? ''),
      sport: sport,
      league: league,
    );
  }

  String get formattedStatus {
    if (isManualEnded) return 'FINAL';
    if (isLive) {
      // Trust the ESPN API's natively sport-aware status text (shortDetail/detail)
      // This correctly handles "Top 3rd" (MLB), "1st - 10:20" (NBA/NFL), "Halftime", etc.
      return statusText ?? 'LIVE';
    }
    if (isCompleted) return 'FINAL';
    return startTimeLocal ?? 'PRE';
  }

  /// Special check for "over but still shows live"
  bool get isActuallyLive {
    if (isManualEnded) return false;
    if (!isLive) return false;
    // If API already says completed, it's not live.
    if (isCompleted) return false;

    // Check if statusText says "Final" - sometimes ESPN says "Final" while state is still "in"
    if (statusText?.toUpperCase().contains('FINAL') ?? false) {
      return false;
    }

    return true;
  }

  bool get isEffectivelyCompleted {
    if (isCompleted) return true;
    if (isLive && !isActuallyLive) return true;
    return false;
  }
}

// ---------------------------------------------------------------------------
// ESPN + Daddylive fetch
// ---------------------------------------------------------------------------

class _LeagueData {
  final _League league;
  List<_EspnGame> games;

  _LeagueData({required this.league, required this.games});

  bool get hasGames => games.isNotEmpty;
  bool get hasLive => games.any((g) => g.isLive);
}

// Aggregated Sports fetch
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _fetchWithRetry({int maxRetries = 2}) async {
  for (int i = 0; i < maxRetries; i++) {
    final result = await _fetchAggregatedSports();
    if (result.isNotEmpty) return result;
    if (i < maxRetries - 1) {
      await Future.delayed(const Duration(seconds: 2));
    }
  }
  return {};
}

Future<Map<String, dynamic>> _fetchAggregatedSports() async {
  try {
    final base = caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
    final url = '$base/sports/scoreboard/all';
    final res = await http
        .get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $caffeineApiKey'},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      return {};
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body;
  } catch (e) {
    return {};
  }
}

// ---------------------------------------------------------------------------
// SportsScreen
// ---------------------------------------------------------------------------

class SportsScreen extends StatefulWidget {
  const SportsScreen({super.key});

  @override
  State<SportsScreen> createState() => SportsScreenState();
}

class SportsScreenState extends State<SportsScreen> {
  final FocusNode _refreshNode = FocusNode();
  List<_LeagueData>? _data;
  Map<String, dynamic>? _featuredEvent;
  bool _loading = true;
  String? _error;
  String? _selectedSport;
  List<String> _availableSports = [];

  void requestFocus() {
    _refreshNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allSportsData = await _fetchWithRetry(maxRetries: 2);

      // Fetch all active stream data from Supabase
      final activeStreamResponse = await Supabase.instance.client
          .from('live_streams')
          .select('id, video_url, referrer, sources, is_hidden, is_ended')
          .not('video_url', 'is', null);

      final Map<String, Map<String, dynamic>> streamInfo = {
        for (var item in (activeStreamResponse as List))
          item['id'].toString(): {
            'url': item['video_url']?.toString(),
            'referrer': item['referrer']?.toString(),
            'sources': item['sources'],
            'is_hidden': item['is_hidden'] == true,
            'is_ended': item['is_ended'] == true,
          },
      };

      final activeStreamIds = streamInfo.keys.toSet();

      final leagueData = <_LeagueData>[];
      final sportsSet = <String>{};
      for (var l in _leagues) {
        final key = '${l.sport}:${l.league}';
        final rawData = allSportsData[key];

        List<_EspnGame> games = [];
        if (rawData != null && rawData['events'] != null) {
          final events = rawData['events'] as List<dynamic>;
          games = events
              .whereType<Map<String, dynamic>>()
              .map((e) {
                final id = e['id']?.toString() ?? '';
                final g = _EspnGame.fromJson(
                  e,
                  sport: l.sport,
                  league: l.league,
                );
                final info = streamInfo[id];

                String? effectiveReferrer = info?['referrer']?.toString();
                if (effectiveReferrer == null || effectiveReferrer.isEmpty) {
                  final sources = info?['sources'];
                  if (sources is List && sources.isNotEmpty) {
                    effectiveReferrer = sources.first['referrer']?.toString();
                  }
                }

                return g.copyWith(
                  videoUrl: info?['url'],
                  referrer: effectiveReferrer,
                  sources: info?['sources'],
                  isManualEnded: info?['is_ended'] == true,
                );
              })
              .where(
                (g) =>
                    activeStreamIds.contains(g.id) &&
                    streamInfo[g.id]?['is_hidden'] != true,
              ) // Filter by stream availability and hidden status
              .toList();
        }

        if (games.isNotEmpty) {
          leagueData.add(_LeagueData(league: l, games: games));
          for (var _ in games) {
            sportsSet.add(l.sport.toUpperCase());
          }
        }
      }

      // Sort games within each league: live first, then by date
      for (var ld in leagueData) {
        ld.games.sort((a, b) {
          final now = DateTime.now();

          // Group 1: Upcoming soon (within 30 mins of starting)
          final isAStartingSoon =
              !a.isActuallyLive &&
              !a.isEffectivelyCompleted &&
              a.startTimeUtc != null &&
              a.startTimeUtc!.isAfter(now) &&
              a.startTimeUtc!.difference(now).inMinutes <= 30;
          final isBStartingSoon =
              !b.isActuallyLive &&
              !b.isEffectivelyCompleted &&
              b.startTimeUtc != null &&
              b.startTimeUtc!.isAfter(now) &&
              b.startTimeUtc!.difference(now).inMinutes <= 30;

          if (isAStartingSoon != isBStartingSoon) {
            return isAStartingSoon ? -1 : 1;
          }

          // Group 2: Actually Live games
          if (a.isActuallyLive && !b.isActuallyLive) return -1;
          if (!a.isActuallyLive && b.isActuallyLive) return 1;

          // Group 3: Other scheduled games (not starting soon, not live, not completed)
          final aSched = !a.isActuallyLive && !a.isEffectivelyCompleted;
          final bSched = !b.isActuallyLive && !b.isEffectivelyCompleted;
          if (aSched && !bSched) return -1;
          if (!aSched && bSched) return 1;

          // Group 4: Completed games last (sorted by start time within their group)
          final timeA = a.startTimeUtc;
          final timeB = b.startTimeUtc;
          if (timeA == null && timeB == null) return 0;
          if (timeA == null) return 1;
          if (timeB == null) return -1;

          return timeA.compareTo(timeB);
        });
      }

      // Sort leagues: live games first
      leagueData.sort((a, b) {
        if (a.hasLive && !b.hasLive) return -1;
        if (!a.hasLive && b.hasLive) return 1;
        return 0;
      });

      final active = leagueData;
      // Fetch featured event from Supabase
      Map<String, dynamic>? featured;
      try {
        featured = await Supabase.instance.client
            .from('live_streams')
            .select('*')
            .eq('is_featured', true)
            .eq('is_hidden', false)
            .not('video_url', 'is', null)
            .neq('video_url', '')
            .maybeSingle();
      } catch (e) {
        debugPrint('[SportsScreen] Error fetching featured event: $e');
      }

      if (mounted) {
        setState(() {
          _availableSports = sportsSet.toList()..sort();
          _data = active;
          _featuredEvent = featured;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _refreshNode.dispose();
    super.dispose();
  }

  double _s(BuildContext context, double v) =>
      (v * MediaQuery.of(context).size.width) / 1920;

  @override
  Widget build(BuildContext context) {
    double s(double v) => _s(context, v);
    final now = DateTime.now();
    final dateStr =
        '${_dayName(now.weekday)}, ${_monthName(now.month)} ${now.day}';

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFDC2626)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              'Could not load sports data',
              style: TextStyle(color: Colors.white54, fontSize: s(28)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      );
    }

    final hasSports =
        _featuredEvent != null || (_data != null && _data!.isNotEmpty);

    if (!hasSports) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sports_soccer_outlined,
              color: Colors.white24,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              'No Live Events currently available',
              style: TextStyle(
                color: Colors.white54,
                fontSize: s(32),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Check back later for live games and events.',
              style: TextStyle(color: Colors.white24, fontSize: s(24)),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(s(48)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Sports',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: s(56),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: s(8)),
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: s(24),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              _RefreshButton(onTap: load, focusNode: _refreshNode),
            ],
          ),
          SizedBox(height: s(40)),
          if (_featuredEvent != null &&
              (_selectedSport == null ||
                  _featuredEvent!['sport']?.toString().toUpperCase() ==
                      _selectedSport)) ...[
            _buildFeaturedCard(s),
            SizedBox(height: s(48)),
          ],
          _buildSportFilters(s),
          SizedBox(height: s(40)),
          if (_data != null) ..._buildCategorizedSections(s),
        ],
      ),
    );
  }

  Widget _buildSportFilters(double Function(double) s) {
    return SizedBox(
      height: s(60),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'ALL',
            selected: _selectedSport == null,
            scale: s,
            onTap: () => setState(() => _selectedSport = null),
          ),
          SizedBox(width: s(16)),
          ..._availableSports.map(
            (sport) => Padding(
              padding: EdgeInsets.only(right: s(16)),
              child: _FilterChip(
                label: sport,
                selected: _selectedSport == sport,
                scale: s,
                onTap: () => setState(() => _selectedSport = sport),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategorizedSections(double Function(double) s) {
    if (_data == null) return [];

    final allGames = <_EspnGame, _League>{};
    for (var ld in _data!) {
      if (_selectedSport != null &&
          ld.league.sport.toUpperCase() != _selectedSport) {
        continue;
      }
      for (var g in ld.games) {
        allGames[g] = ld.league;
      }
    }

    final liveGames = allGames.entries
        .where((e) => e.key.isActuallyLive)
        .toList();
    final upcomingGames = allGames.entries
        .where((e) => !e.key.isActuallyLive && !e.key.isEffectivelyCompleted)
        .toList();
    final completedGames = allGames.entries
        .where((e) => e.key.isEffectivelyCompleted)
        .toList();

    return [
      if (liveGames.isNotEmpty)
        _StatusSection(
          title: 'LIVE NOW',
          games: liveGames,
          scale: s,
          isLive: true,
        ),
      if (upcomingGames.isNotEmpty)
        _StatusSection(title: 'UPCOMING', games: upcomingGames, scale: s),
      if (completedGames.isNotEmpty)
        _StatusSection(title: 'COMPLETED', games: completedGames, scale: s),
      if (liveGames.isEmpty && upcomingGames.isEmpty && completedGames.isEmpty)
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: s(100)),
            child: Text(
              'No games found for this category',
              style: TextStyle(color: Colors.white24, fontSize: s(28)),
            ),
          ),
        ),
    ];
  }

  String _dayName(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _monthName(int m) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  Widget _buildFeaturedCard(double Function(double) s) {
    bool focused = false;
    final color = const Color(0xFFDC2626);
    final title = _featuredEvent!['title'] ?? 'Featured Event';
    final sport = _featuredEvent!['sport'] ?? 'LIVE';
    final poster =
        _featuredEvent!['poster_url'] ?? _featuredEvent!['thumbnail_url'];

    return StatefulBuilder(
      builder: (context, setState) {
        return FocusableActionDetector(
          onShowFocusHighlight: (v) => setState(() => focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                if (_featuredEvent!['video_url'] != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(
                        url: _featuredEvent!['video_url'],
                        title: title,
                        item: _featuredEvent,
                        isMovie: false,
                        referrer: _featuredEvent!['referrer'],
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
          },
          child: InkWell(
            onTap: () {
              if (_featuredEvent!['video_url'] != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlayerScreen(
                      url: _featuredEvent!['video_url'],
                      title: title,
                      item: _featuredEvent,
                      isMovie: false,
                      referrer: _featuredEvent!['referrer'],
                      allProviders: (_featuredEvent!['sources'] as List?)
                          ?.map(
                            (s) => {
                              'name': s['name']?.toString() ?? 'Source',
                              'code': s['url']?.toString() ?? '',
                              'referrer': s['referrer']?.toString() ?? '',
                            },
                          )
                          .toList()
                          .cast<Map<String, String>>(),
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(s(24)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: s(450),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s(24)),
                boxShadow: [
                  if (focused)
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: s(30),
                      spreadRadius: s(5),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(s(24)),
                child: Stack(
                  children: [
                    // Background Image / Gradient
                    if (poster != null)
                      Positioned.fill(
                        child: Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _gradientBack(color),
                        ),
                      )
                    else
                      _gradientBack(color),

                    // Dark Overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.9),
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: EdgeInsets.all(s(32)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: s(16),
                              vertical: s(8),
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(s(8)),
                            ),
                            child: Text(
                              'FEATURED LIVE EVENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(16),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          SizedBox(height: s(20)),
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(56),
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(height: s(12)),
                          Row(
                            children: [
                              Icon(
                                Icons.sports_soccer,
                                color: Colors.white70,
                                size: s(24),
                              ),
                              SizedBox(width: s(12)),
                              Text(
                                sport,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: s(24),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: s(32)),
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: s(32),
                                  vertical: s(16),
                                ),
                                decoration: BoxDecoration(
                                  color: focused
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(s(12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.play_arrow_rounded,
                                      color: focused
                                          ? Colors.black
                                          : Colors.white,
                                      size: s(32),
                                    ),
                                    SizedBox(width: s(12)),
                                    Text(
                                      'WATCH NOW',
                                      style: TextStyle(
                                        color: focused
                                            ? Colors.black
                                            : Colors.white,
                                        fontSize: s(24),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Focus Border
                    if (focused)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s(24)),
                            border: Border.all(
                              color: Colors.white,
                              width: s(4),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gradientBack(Color color) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.3), Colors.black],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// League section widget
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Status section widget (Categorized by Live/Upcoming/Completed)
// ---------------------------------------------------------------------------

class _StatusSection extends StatelessWidget {
  final String title;
  final List<MapEntry<_EspnGame, _League>> games;
  final double Function(double) scale;
  final bool isLive;

  const _StatusSection({
    required this.title,
    required this.games,
    required this.scale,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;

    return Padding(
      padding: EdgeInsets.only(bottom: s(48)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              if (isLive)
                Container(
                  width: s(4),
                  height: s(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(s(2)),
                  ),
                ),
              if (isLive) SizedBox(width: s(12)),
              Text(
                title,
                style: TextStyle(
                  color: isLive ? const Color(0xFFDC2626) : Colors.white70,
                  fontSize: s(34),
                  fontWeight: FontWeight.w900,
                  letterSpacing: isLive ? 1.2 : 0,
                ),
              ),
              const Spacer(),
              Text(
                '${games.length} EVENTS',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: s(18),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: s(24)),
          // Games scroll
          SizedBox(
            height: s(200),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: games.length,
              separatorBuilder: (_, _) => SizedBox(width: s(16)),
              itemBuilder: (ctx, i) {
                final game = games[i].key;
                final league = games[i].value;
                return _GameCard(
                  game: game,
                  league: league,
                  accentColor: league.color,
                  scale: s,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final double Function(double) scale;
  const _LiveBadge({required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(6)),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(s(20)),
        border: Border.all(
          color: const Color(0xFFDC2626).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: s(8),
            height: s(8),
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: s(6)),
          Text(
            'LIVE',
            style: TextStyle(
              color: const Color(0xFFDC2626),
              fontSize: s(14),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game card
// ---------------------------------------------------------------------------

class _GameCard extends StatefulWidget {
  final _EspnGame game;
  final _League league;
  final Color accentColor;
  final double Function(double) scale;

  const _GameCard({
    required this.game,
    required this.league,
    required this.accentColor,
    required this.scale,
  });

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _focused = false;

  void _onTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SportsGameDetailScreen(
          sport: widget.league.sport,
          league: widget.league.league,
          eventId: widget.game.id,
          gameName: widget.game.name,
          sources: widget.game.sources,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final g = widget.game;

    return InkWell(
      onTap: _onTap,
      onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: BorderRadius.circular(s(16)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: s(360),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accentColor.withValues(alpha: 0.15)
                : const Color(0xFF0B0F14),
            borderRadius: BorderRadius.circular(s(16)),
            border: Border.all(
              color: _focused
                  ? widget.accentColor
                  : (g.isLive
                        ? const Color(0xFFDC2626).withValues(alpha: 0.4)
                        : Colors.white12),
              width: _focused ? 2 : 1,
            ),
          ),
          padding: EdgeInsets.all(s(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (g.isActuallyLive) ...[
                        Container(
                          width: s(8),
                          height: s(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDC2626),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: s(8)),
                        Text(
                          g.formattedStatus,
                          style: TextStyle(
                            color: const Color(0xFFDC2626),
                            fontSize: s(15),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ] else if (g.isEffectivelyCompleted) ...[
                        Text(
                          'FINAL',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: s(14),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          Icons.schedule_rounded,
                          color: Colors.white38,
                          size: s(16),
                        ),
                        SizedBox(width: s(6)),
                        Text(
                          g.startTimeLocal ?? '—',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: s(15),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: s(10),
                      vertical: s(4),
                    ),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(s(6)),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      widget.league.name,
                      style: TextStyle(
                        color: widget.accentColor,
                        fontSize: s(12),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: s(16)),
              // Away team
              _TeamRow(
                name: g.awayTeam ?? 'Away',
                logoUrl: g.awayLogo,
                score: g.isLive || g.isCompleted ? g.awayScore : null,
                scale: s,
              ),
              SizedBox(height: s(10)),
              // Home team
              _TeamRow(
                name: g.homeTeam ?? 'Home',
                logoUrl: g.homeLogo,
                score: g.isLive || g.isCompleted ? g.homeScore : null,
                scale: s,
              ),
            ],
          ),
        ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final String? score;
  final double Function(double) scale;

  const _TeamRow({
    required this.name,
    this.logoUrl,
    this.score,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      children: [
        if (logoUrl != null && logoUrl!.isNotEmpty)
          Image.network(
            logoUrl!,
            width: s(36),
            height: s(36),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(s),
          )
        else
          _placeholder(s),
        SizedBox(width: s(12)),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: Colors.white,
              fontSize: s(18),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null)
          Text(
            score!,
            style: TextStyle(
              color: Colors.white,
              fontSize: s(22),
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }

  Widget _placeholder(double Function(double) s) => Container(
    width: s(36),
    height: s(36),
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(s(6)),
    ),
    child: Icon(Icons.sports, color: Colors.white38, size: s(20)),
  );
}

// ---------------------------------------------------------------------------
// Filter Chip Component
// ---------------------------------------------------------------------------

class _FilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final double Function(double) scale;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.scale,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final isSelected = widget.selected;

    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: BorderRadius.circular(s(30)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(12)),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFDC2626)
                : (_focused
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(s(30)),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (_focused ? Colors.white70 : Colors.white10),
              width: s(2),
            ),
            boxShadow: [
              if (_focused || isSelected)
                BoxShadow(
                  color: (isSelected ? const Color(0xFFDC2626) : Colors.white)
                      .withValues(alpha: 0.2),
                  blurRadius: s(16),
                  spreadRadius: s(2),
                ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : (_focused ? Colors.white : Colors.white54),
              fontSize: s(20),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const _RefreshButton({required this.onTap, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double s(double v) => (v * width) / 1920;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(16)),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(s(12)),
                border: Border.all(
                  color: focused ? Colors.white : Colors.white24,
                  width: s(2),
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.2),
                          blurRadius: s(12),
                          spreadRadius: s(2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    color: focused ? Colors.black : Colors.white70,
                    size: s(32),
                  ),
                  SizedBox(width: s(12)),
                  Text(
                    'Refresh',
                    style: TextStyle(
                      color: focused ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: s(24),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
