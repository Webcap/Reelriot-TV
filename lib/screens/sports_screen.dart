import 'dart:convert';
import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
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
  final List<String> channelKeywords; // daddylive keyword matching

  const _League({
    required this.name,
    required this.sport,
    required this.league,
    required this.icon,
    required this.color,
    required this.channelKeywords,
  });
}

const _leagues = [
  // ── Basketball ─────────────────────────────────────────────────────────
  _League(name: 'NBA', sport: 'basketball', league: 'nba', icon: Icons.sports_basketball, color: Color(0xFFF97316), channelKeywords: ['nba', 'tnt', 'espn nba', 'nbatv']),
  _League(name: 'NCAAB (Men)', sport: 'basketball', league: 'mens-college-basketball', icon: Icons.sports_basketball, color: Color(0xFFF59E0B), channelKeywords: ['espn', 'cbs', 'tbs', 'tnt', 'acc', 'sec']),
  _League(name: 'NCAAW (Women)', sport: 'basketball', league: 'womens-college-basketball', icon: Icons.sports_basketball, color: Color(0xFFEC4899), channelKeywords: ['espn', 'espnu']),
  _League(name: 'WNBA', sport: 'basketball', league: 'wnba', icon: Icons.sports_basketball, color: Color(0xFFE11D48), channelKeywords: ['wnba', 'espn']),
  // ── American Football ───────────────────────────────────────────────────
  _League(name: 'NFL', sport: 'football', league: 'nfl', icon: Icons.sports_football, color: Color(0xFF8B5CF6), channelKeywords: ['nfl', 'nfl network', 'redzone', 'espn nfl']),
  _League(name: 'College Football', sport: 'football', league: 'college-football', icon: Icons.sports_football, color: Color(0xFF7C3AED), channelKeywords: ['espn', 'abc', 'cbs', 'fox', 'sec', 'acc']),
  _League(name: 'CFL', sport: 'football', league: 'cfl', icon: Icons.sports_football, color: Color(0xFFA78BFA), channelKeywords: ['tsn', 'cfl']),
  // ── Baseball ────────────────────────────────────────────────────────────
  _League(name: 'MLB', sport: 'baseball', league: 'mlb', icon: Icons.sports_baseball, color: Color(0xFF3B82F6), channelKeywords: ['mlb', 'mlb network', 'baseball', 'fox sports']),
  // ── Hockey ──────────────────────────────────────────────────────────────
  _League(name: 'NHL', sport: 'hockey', league: 'nhl', icon: Icons.sports_hockey, color: Color(0xFF06B6D4), channelKeywords: ['nhl', 'nhl network', 'hockey', 'espn nhl']),
  // ── Soccer ──────────────────────────────────────────────────────────────
  _League(name: 'Premier League', sport: 'soccer', league: 'eng.1', icon: Icons.sports_soccer, color: Color(0xFF22C55E), channelKeywords: ['sky sports premier', 'premier league', 'peacock', 'nbcsn']),
  _League(name: 'La Liga', sport: 'soccer', league: 'esp.1', icon: Icons.sports_soccer, color: Color(0xFFEF4444), channelKeywords: ['la liga', 'bein sports', 'espn']),
  _League(name: 'Bundesliga', sport: 'soccer', league: 'ger.1', icon: Icons.sports_soccer, color: Color(0xFFD97706), channelKeywords: ['bundesliga', 'espn', 'bein']),
  _League(name: 'Serie A', sport: 'soccer', league: 'ita.1', icon: Icons.sports_soccer, color: Color(0xFF10B981), channelKeywords: ['serie a', 'paramount', 'cbssn']),
  _League(name: 'Ligue 1', sport: 'soccer', league: 'fra.1', icon: Icons.sports_soccer, color: Color(0xFF0EA5E9), channelKeywords: ['ligue 1', 'bein', 'canal']),
  _League(name: 'Champions League', sport: 'soccer', league: 'uefa.champions', icon: Icons.sports_soccer, color: Color(0xFF6366F1), channelKeywords: ['champions league', 'sky sports', 'bein', 'cbs']),
  _League(name: 'Europa League', sport: 'soccer', league: 'uefa.europa', icon: Icons.sports_soccer, color: Color(0xFFF97316), channelKeywords: ['europa league', 'bein', 'cbs']),
  _League(name: 'MLS', sport: 'soccer', league: 'usa.1', icon: Icons.sports_soccer, color: Color(0xFF38BDF8), channelKeywords: ['mls', 'apple tv', 'fox sports']),
  _League(name: 'Liga MX', sport: 'soccer', league: 'mex.1', icon: Icons.sports_soccer, color: Color(0xFF84CC16), channelKeywords: ['liga mx', 'univision', 'tudn', 'fox deportes']),
  // ── Racing ──────────────────────────────────────────────────────────────
  _League(name: 'Formula 1', sport: 'racing', league: 'f1', icon: Icons.speed, color: Color(0xFFDC2626), channelKeywords: ['sky sports f1', 'espn f1', 'f1 tv']),
  _League(name: 'NASCAR Cup', sport: 'racing', league: 'nascar-premier', icon: Icons.speed, color: Color(0xFF78716C), channelKeywords: ['nascar', 'fox sports', 'nbc sports']),
  _League(name: 'IndyCar', sport: 'racing', league: 'irl', icon: Icons.speed, color: Color(0xFF0284C7), channelKeywords: ['indycar', 'nbc', 'peacock']),
  // ── Tennis ──────────────────────────────────────────────────────────────
  _League(name: 'Tennis (ATP)', sport: 'tennis', league: 'atp', icon: Icons.sports_tennis, color: Color(0xFFFBBF24), channelKeywords: ['tennis channel', 'espn tennis', 'tennis']),
  _League(name: 'Tennis (WTA)', sport: 'tennis', league: 'wta', icon: Icons.sports_tennis, color: Color(0xFFF472B6), channelKeywords: ['tennis channel', 'espn']),
  // ── Golf ────────────────────────────────────────────────────────────────
  _League(name: 'PGA Tour', sport: 'golf', league: 'pga', icon: Icons.sports_golf, color: Color(0xFF4ADE80), channelKeywords: ['golf channel', 'pga', 'cbs sports', 'espn golf']),
  _League(name: 'LIV Golf', sport: 'golf', league: 'liv', icon: Icons.sports_golf, color: Color(0xFF86EFAC), channelKeywords: ['liv golf', 'cw']),
  // ── Rugby ───────────────────────────────────────────────────────────────
  _League(name: 'Rugby Union', sport: 'rugby-union', league: 'intl', icon: Icons.sports_rugby, color: Color(0xFF6EE7B7), channelKeywords: ['sky sports rugby', 'rugby', 'bein']),
  // ── MMA / Combat ────────────────────────────────────────────────────────
  _League(name: 'UFC / MMA', sport: 'mma', league: 'ufc', icon: Icons.sports_mma, color: Color(0xFFDC2626), channelKeywords: ['ufc', 'ppv', 'espn mma', 'fight']),
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

    String? teamName(Map<String, dynamic>? c) => (c?['team'] as Map?)?.entries
        .firstWhere((e) => e.key == 'displayName', orElse: () => const MapEntry('', ''))
        .value?.toString();
    String? teamLogo(Map<String, dynamic>? c) => (c?['team'] as Map?)?.entries
        .firstWhere((e) => e.key == 'logo', orElse: () => const MapEntry('', ''))
        .value?.toString();
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
  final List<_DlChannel> channels;

  const _LeagueData({required this.league, required this.games, required this.channels});

  bool get hasGames => games.isNotEmpty;
  bool get hasChannels => channels.isNotEmpty;
  bool get hasLive => games.any((g) => g.isLive);
}

class _DlChannel {
  final int id;
  final String name;
  _DlChannel({required this.id, required this.name});
}

class _DaddyliveResponse {
  final String baseUrl;
  final String trailingUrl;
  final String referrer;
  final String userAgent;
  final List<_DlChannel> channels;
  _DaddyliveResponse({required this.baseUrl, required this.trailingUrl, required this.referrer, required this.userAgent, required this.channels});
}

Future<_DaddyliveResponse?> _fetchDaddyliveChannels() async {
  try {
    final base = caffeineApiUrl.endsWith('/') ? caffeineApiUrl : '$caffeineApiUrl/';
    final res = await http.get(Uri.parse('${base}daddylive/live')).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['channels'] as List<dynamic>? ?? [];
    final channels = raw.whereType<Map<String, dynamic>>().map((e) {
      final id = e['id'];
      final name = e['channel_name']?.toString() ?? '';
      if (id is int) return _DlChannel(id: id, name: name);
      return null;
    }).whereType<_DlChannel>().toList();
    return _DaddyliveResponse(
      baseUrl: data['base_url']?.toString() ?? '',
      trailingUrl: data['trailing_url']?.toString() ?? '',
      referrer: data['referrer']?.toString() ?? 'https://lewblivehdplay.ru/',
      userAgent: data['user_agent']?.toString() ?? 'Mozilla/5.0',
      channels: channels,
    );
  } catch (_) {
    return null;
  }
}

Future<List<_EspnGame>> _fetchEspnGames(String sport, String league) async {
  try {
    // Pass today's date explicitly so ESPN only returns today's events
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final url = 'https://site.api.espn.com/apis/site/v2/sports/$sport/$league/scoreboard?dates=$dateStr';
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final events = data['events'] as List<dynamic>? ?? [];
    return events.whereType<Map<String, dynamic>>().map(_EspnGame.fromJson).toList();
  } catch (_) {
    return [];
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
  _DaddyliveResponse? _dl;
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
      // Fetch daddylive channels + all ESPN leagues concurrently
      final results = await Future.wait([
        _fetchDaddyliveChannels(),
        ..._leagues.map((l) => _fetchEspnGames(l.sport, l.league)),
      ]);

      final dl = results[0] as _DaddyliveResponse?;
      final leagueData = <_LeagueData>[];
      for (var i = 0; i < _leagues.length; i++) {
        final games = results[i + 1] as List<_EspnGame>;
        final keywords = _leagues[i].channelKeywords.map((k) => k.toLowerCase()).toList();
        final channels = (dl?.channels ?? <_DlChannel>[]).where((ch) {
          final name = ch.name.toLowerCase();
          return keywords.any((k) => name.contains(k));
        }).toList();
        leagueData.add(_LeagueData(league: _leagues[i], games: games, channels: channels));
      }

      // Only show leagues that have games today
      final active = leagueData.where((d) => d.hasGames).toList();
      if (mounted) {
        setState(() {
          _data = active.isEmpty ? leagueData : active;
          _dl = dl;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _directHls(int channelId) {
    if (_dl == null) return '';
    final base = _dl!.baseUrl.endsWith('/') ? _dl!.baseUrl : '${_dl!.baseUrl}/';
    return '$base$channelId${_dl!.trailingUrl}';
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
              onChannelTap: (ch) {
                final url = _directHls(ch.id);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    url: url,
                    title: ch.name,
                    item: null,
                    isMovie: false,
                  ),
                ));
              },
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
  final void Function(_DlChannel ch) onChannelTap;

  const _LeagueSection({required this.data, required this.scale, required this.onChannelTap});

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
              const Spacer(),
              if (data.hasChannels)
                _WatchButton(
                  channels: data.channels,
                  color: league.color,
                  scale: s,
                  onTap: onChannelTap,
                ),
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

class _WatchButton extends StatefulWidget {
  final List<_DlChannel> channels;
  final Color color;
  final double Function(double) scale;
  final void Function(_DlChannel ch) onTap;

  const _WatchButton({required this.channels, required this.color, required this.scale, required this.onTap});

  @override
  State<_WatchButton> createState() => _WatchButtonState();
}

class _WatchButtonState extends State<_WatchButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
          _pick(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => _pick(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(10)),
          decoration: BoxDecoration(
            color: _focused ? widget.color : widget.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(s(10)),
            border: Border.all(color: widget.color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: _focused ? Colors.white : widget.color, size: s(22)),
              SizedBox(width: s(8)),
              Text('Watch', style: TextStyle(color: _focused ? Colors.white : widget.color, fontSize: s(18), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  void _pick(BuildContext context) {
    if (widget.channels.length == 1) {
      widget.onTap(widget.channels.first);
      return;
    }
    showDialog<_DlChannel>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Select Channel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.channels.length,
            itemBuilder: (_, i) {
              final ch = widget.channels[i];
              return ListTile(
                leading: const Icon(Icons.live_tv, color: Color(0xFFDC2626)),
                title: Text(ch.name, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onTap(ch);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game card
// ---------------------------------------------------------------------------

class _GameCard extends StatefulWidget {
  final _EspnGame game;
  final Color accentColor;
  final double Function(double) scale;

  const _GameCard({required this.game, required this.accentColor, required this.scale});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final g = widget.game;

    return Focus(
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
