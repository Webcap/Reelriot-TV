import 'dart:convert';
import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/screens/sports_game_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// ESPN league config
// ---------------------------------------------------------------------------

class _League {
  final String name;
  final String sport;     // ESPN path segment (e.g. basketball)
  final String league;    // ESPN path segment (e.g. nba)
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
  _League(name: 'NBA', sport: 'basketball', league: 'nba', icon: Icons.sports_basketball, color: Color(0xFFF97316)),
  _League(name: 'NCAAB (Men)', sport: 'basketball', league: 'mens-college-basketball', icon: Icons.sports_basketball, color: Color(0xFFF59E0B)),
  _League(name: 'NCAAW (Women)', sport: 'basketball', league: 'womens-college-basketball', icon: Icons.sports_basketball, color: Color(0xFFEC4899)),
  _League(name: 'WNBA', sport: 'basketball', league: 'wnba', icon: Icons.sports_basketball, color: Color(0xFFE11D48)),
  // ── American Football ───────────────────────────────────────────────────
  _League(name: 'NFL', sport: 'football', league: 'nfl', icon: Icons.sports_football, color: Color(0xFF8B5CF6)),
  _League(name: 'College Football', sport: 'football', league: 'college-football', icon: Icons.sports_football, color: Color(0xFF7C3AED)),
  _League(name: 'CFL', sport: 'football', league: 'cfl', icon: Icons.sports_football, color: Color(0xFFA78BFA)),
  // ── Baseball ────────────────────────────────────────────────────────────
  _League(name: 'MLB', sport: 'baseball', league: 'mlb', icon: Icons.sports_baseball, color: Color(0xFF3B82F6)),
  // ── Hockey ──────────────────────────────────────────────────────────────
  _League(name: 'NHL', sport: 'hockey', league: 'nhl', icon: Icons.sports_hockey, color: Color(0xFF06B6D4)),
  // ── Soccer ──────────────────────────────────────────────────────────────
  _League(name: 'Premier League', sport: 'soccer', league: 'eng.1', icon: Icons.sports_soccer, color: Color(0xFF22C55E)),
  _League(name: 'La Liga', sport: 'soccer', league: 'esp.1', icon: Icons.sports_soccer, color: Color(0xFFEF4444)),
  _League(name: 'Bundesliga', sport: 'soccer', league: 'ger.1', icon: Icons.sports_soccer, color: Color(0xFFD97706)),
  _League(name: 'Serie A', sport: 'soccer', league: 'ita.1', icon: Icons.sports_soccer, color: Color(0xFF10B981)),
  _League(name: 'Ligue 1', sport: 'soccer', league: 'fra.1', icon: Icons.sports_soccer, color: Color(0xFF0EA5E9)),
  _League(name: 'Champions League', sport: 'soccer', league: 'uefa.champions', icon: Icons.sports_soccer, color: Color(0xFF6366F1)),
  _League(name: 'Europa League', sport: 'soccer', league: 'uefa.europa', icon: Icons.sports_soccer, color: Color(0xFFF97316)),
  _League(name: 'MLS', sport: 'soccer', league: 'usa.1', icon: Icons.sports_soccer, color: Color(0xFF38BDF8)),
  _League(name: 'Liga MX', sport: 'soccer', league: 'mex.1', icon: Icons.sports_soccer, color: Color(0xFF84CC16)),
  // ── Racing ──────────────────────────────────────────────────────────────
  _League(name: 'Formula 1', sport: 'racing', league: 'f1', icon: Icons.speed, color: Color(0xFFDC2626)),
  _League(name: 'NASCAR Cup', sport: 'racing', league: 'nascar-premier', icon: Icons.speed, color: Color(0xFF78716C)),
  _League(name: 'IndyCar', sport: 'racing', league: 'irl', icon: Icons.speed, color: Color(0xFF0284C7)),
  // ── Tennis ──────────────────────────────────────────────────────────────
  _League(name: 'Tennis (ATP)', sport: 'tennis', league: 'atp', icon: Icons.sports_tennis, color: Color(0xFFFBBF24)),
  _League(name: 'Tennis (WTA)', sport: 'tennis', league: 'wta', icon: Icons.sports_tennis, color: Color(0xFFF472B6)),
  // ── Golf ────────────────────────────────────────────────────────────────
  _League(name: 'PGA Tour', sport: 'golf', league: 'pga', icon: Icons.sports_golf, color: Color(0xFF4ADE80)),
  _League(name: 'LIV Golf', sport: 'golf', league: 'liv', icon: Icons.sports_golf, color: Color(0xFF86EFAC)),
  // ── Rugby ───────────────────────────────────────────────────────────────
  _League(name: 'Rugby Union', sport: 'rugby-union', league: 'intl', icon: Icons.sports_rugby, color: Color(0xFF6EE7B7)),
  // ── MMA / Combat ────────────────────────────────────────────────────────
  _League(name: 'UFC / MMA', sport: 'mma', league: 'ufc', icon: Icons.sports_mma, color: Color(0xFFDC2626)),
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
  });

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

  factory _EspnGame.fromJson(Map<String, dynamic> json) {
    final comps = json['competitions'] as List<dynamic>? ?? [];
    final comp = comps.isNotEmpty && comps.first is Map ? comps.first as Map<String, dynamic> : <String, dynamic>{};
    final compets = comp['competitors'] as List<dynamic>? ?? [];

    Map<String, dynamic>? away, home;
    for (final c in compets) {
      if (c is Map<String, dynamic>) {
        if (c['homeAway'] == 'away') away = c;
        if (c['homeAway'] == 'home') home = c;
      }
    }

    String? teamName(Map<String, dynamic>? c) {
      final team = c?['team'] as Map<String, dynamic>?;
      return team?['displayName']?.toString();
    }
    String? teamLogo(Map<String, dynamic>? c) {
      final team = c?['team'] as Map<String, dynamic>?;
      return team?['logo']?.toString();
    }
    String? teamScore(Map<String, dynamic>? c) => c?['score']?.toString();

    final statusJson = comp['status'] as Map<String, dynamic>?;
    final statusType = statusJson?['type'] as Map<String, dynamic>?;
    final state = statusType?['state']?.toString() ?? 'pre';
    final isLive = state == 'in';
    final isCompleted = state == 'post';
    final awayS = teamScore(away);
    final homeS = teamScore(home);
    final scoreLine = (awayS != null && homeS != null) ? '$awayS  -  $homeS' : null;

    return _EspnGame(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName: json['shortName']?.toString() ?? '',
      isLive: isLive,
      isCompleted: isCompleted,
      scoreLine: isLive || isCompleted ? scoreLine : null,
      statusText: statusJson?['shortDetail']?.toString() ?? statusJson?['detail']?.toString(),
      startTimeLocal: _formatTime(json['date']?.toString()),
      awayTeam: teamName(away),
      homeTeam: teamName(home),
      awayLogo: teamLogo(away),
      homeLogo: teamLogo(home),
      awayScore: awayS,
      homeScore: homeS,
    );
  }
}

// ---------------------------------------------------------------------------
// ESPN + Daddylive fetch
// ---------------------------------------------------------------------------

class _LeagueData {
  final _League league;
  final List<_EspnGame> games;

  const _LeagueData({required this.league, required this.games});

  bool get hasGames => games.isNotEmpty;
  bool get hasLive => games.any((g) => g.isLive);
}

// Aggregated Sports fetch
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _fetchAggregatedSports() async {
  try {
    final base = caffeineApiUrl.endsWith('/') ? caffeineApiUrl : '$caffeineApiUrl/';
    // The aggregator handles the date and fetches all leagues in parallel
    final res = await http.get(Uri.parse('${base}sports/scoreboard/all')).timeout(const Duration(seconds: 15));
    debugPrint('[SportsScreen] Fetching aggregated sports from: ${base}sports/scoreboard/all');
    if (res.statusCode != 200) {
      debugPrint('[SportsScreen] Error fetching aggregated sports: ${res.statusCode}');
      return {};
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    debugPrint('[SportsScreen] Successfully fetched aggregated sports. Leagues in response: ${body.keys.length}');
    return body;
  } catch (_) {
    return {};
  }
}

// ---------------------------------------------------------------------------
// SportsScreen
// ---------------------------------------------------------------------------

class SportsScreen extends StatefulWidget {
  const SportsScreen({super.key});

  @override
  State<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends State<SportsScreen> {
  List<_LeagueData>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch aggregated sports from caffeine-api
      final allSportsData = await _fetchAggregatedSports();
      
      final leagueData = <_LeagueData>[];
      for (var l in _leagues) {
        final key = '${l.sport}:${l.league}';
        final rawData = allSportsData[key];
        
        List<_EspnGame> games = [];
        if (rawData != null && rawData['events'] != null) {
          final events = rawData['events'] as List<dynamic>;
          games = events.whereType<Map<String, dynamic>>().map(_EspnGame.fromJson).toList();
        }

        leagueData.add(_LeagueData(league: l, games: games));
        if (games.isNotEmpty) {
          debugPrint('[SportsScreen] League ${l.name}: ${games.length} games found.');
        }
      }

      // Only show leagues that have games today
      final active = leagueData.where((d) => d.hasGames).toList();
      if (mounted) {
        setState(() {
          _data = active.isEmpty ? leagueData : active;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[SportsScreen] CRITICAL ERROR IN LOAD: $e');
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }


  double _s(BuildContext context, double v) =>
      (v * MediaQuery.of(context).size.width) / 1920;

  @override
  Widget build(BuildContext context) {
    final s = (double v) => _s(context, v);
    final now = DateTime.now();
    final dateStr = '${_dayName(now.weekday)}, ${_monthName(now.month)} ${now.day}';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)));
    }

    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 64),
          const SizedBox(height: 16),
          Text('Could not load sports data', style: TextStyle(color: Colors.white54, fontSize: s(28))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          ),
        ],
      ));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(s(48)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Sports', style: TextStyle(color: Colors.white, fontSize: s(56), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          SizedBox(height: s(8)),
          Text(dateStr, style: TextStyle(color: Colors.white38, fontSize: s(24), fontWeight: FontWeight.w500)),
          SizedBox(height: s(40)),
          if (_data != null)
            ..._data!.map((d) => _LeagueSection(
              data: d,
              scale: s,
            )).toList(),
        ],
      ),
    );
  }

  String _dayName(int d) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _monthName(int m) => ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

// ---------------------------------------------------------------------------
// League section widget
// ---------------------------------------------------------------------------

class _LeagueSection extends StatelessWidget {
  final _LeagueData data;
  final double Function(double) scale;

  const _LeagueSection({required this.data, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final league = data.league;

    return Padding(
      padding: EdgeInsets.only(bottom: s(48)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(s(10)),
                decoration: BoxDecoration(
                  color: league.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(s(10)),
                ),
                child: Icon(league.icon, color: league.color, size: s(32)),
              ),
              SizedBox(width: s(16)),
              Text(league.name, style: TextStyle(color: Colors.white, fontSize: s(34), fontWeight: FontWeight.w800)),
              SizedBox(width: s(16)),
              if (data.hasLive)
                _LiveBadge(scale: s),
            ],
          ),
          SizedBox(height: s(20)),
          // Games list
          if (data.hasGames)
            SizedBox(
              height: s(200),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.games.length,
                separatorBuilder: (_, __) => SizedBox(width: s(16)),
                itemBuilder: (ctx, i) => _GameCard(
                  game: data.games[i],
                  league: league,
                  accentColor: league.color,
                  scale: s,
                ),
              ),
            )
          else
            Container(
              padding: EdgeInsets.symmetric(vertical: s(24)),
              child: Text('No games scheduled today', style: TextStyle(color: Colors.white30, fontSize: s(20))),
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
        border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: s(8), height: s(8), decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle)),
          SizedBox(width: s(6)),
          Text('LIVE', style: TextStyle(color: const Color(0xFFDC2626), fontSize: s(14), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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

  const _GameCard({required this.game, required this.league, required this.accentColor, required this.scale});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final g = widget.game;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SportsGameDetailScreen(
              sport: widget.league.sport,
              league: widget.league.league,
              eventId: widget.game.id,
              gameName: widget.game.name,
            ),
          ),
        );
      },
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: s(360),
        decoration: BoxDecoration(
          color: _focused ? widget.accentColor.withValues(alpha: 0.15) : const Color(0xFF0B0F14),
          borderRadius: BorderRadius.circular(s(16)),
          border: Border.all(
            color: _focused ? widget.accentColor : (g.isLive ? const Color(0xFFDC2626).withValues(alpha: 0.4) : Colors.white12),
            width: _focused ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(s(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row
            Row(
              children: [
                if (g.isLive) ...[
                  Container(width: s(8), height: s(8), decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle)),
                  SizedBox(width: s(6)),
                  Text(g.statusText ?? 'LIVE', style: TextStyle(color: const Color(0xFFDC2626), fontSize: s(14), fontWeight: FontWeight.w700)),
                ] else if (g.isCompleted) ...[
                  Text('FINAL', style: TextStyle(color: Colors.white38, fontSize: s(14), fontWeight: FontWeight.w600)),
                ] else ...[
                  Icon(Icons.schedule_rounded, color: Colors.white38, size: s(16)),
                  SizedBox(width: s(6)),
                  Text(g.startTimeLocal ?? '—', style: TextStyle(color: Colors.white54, fontSize: s(14))),
                ],
                const Spacer(),
                if (g.isLive || g.isCompleted)
                  Text(g.statusText ?? '', style: TextStyle(color: Colors.white38, fontSize: s(13))),
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
    ),
   );
  }
}

class _TeamRow extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final String? score;
  final double Function(double) scale;

  const _TeamRow({required this.name, this.logoUrl, this.score, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      children: [
        if (logoUrl != null && logoUrl!.isNotEmpty)
          Image.network(logoUrl!, width: s(36), height: s(36), fit: BoxFit.contain, errorBuilder: (_, __, ___) => _placeholder(s))
        else
          _placeholder(s),
        SizedBox(width: s(12)),
        Expanded(
          child: Text(name, style: TextStyle(color: Colors.white, fontSize: s(18), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (score != null)
          Text(score!, style: TextStyle(color: Colors.white, fontSize: s(22), fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _placeholder(double Function(double) s) => Container(
    width: s(36), height: s(36),
    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(s(6))),
    child: Icon(Icons.sports, color: Colors.white38, size: s(20)),
  );
}
