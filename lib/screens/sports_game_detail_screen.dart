import 'dart:convert';
import 'package:reelriot_tv/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/screens/player_screen.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/utils/auth_error_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/widgets/hero_badge.dart';
import 'package:reelriot_tv/widgets/action_button.dart';
import 'package:reelriot_tv/widgets/section_header.dart';
import 'package:reelriot_tv/widgets/full_screen_status.dart';

String? _str(dynamic val) {
  if (val == null) return null;
  if (val is String) return val;
  if (val is Map && val['href'] != null) return val['href'].toString();
  return val.toString();
}

class SportsGameDetailScreen extends StatefulWidget {
  final String sport;
  final String league;
  final String eventId;
  final String? gameName;
  final List<dynamic>? sources;
  final String? baseUrl;
  final http.Client? client;

  const SportsGameDetailScreen({
    super.key,
    required this.sport,
    required this.league,
    required this.eventId,
    this.gameName,
    this.sources,
    this.baseUrl,
    this.client,
  });

  @override
  State<SportsGameDetailScreen> createState() => _SportsGameDetailScreenState();
}

class _SportsGameDetailScreenState extends State<SportsGameDetailScreen> {
  Map<String, dynamic>? _summary;
  bool _isLoading = true;
  String? _error;
  String? _streamUrl;
  String? _streamReferrer;
  List<dynamic>? _sources;

  @override
  void initState() {
    super.initState();
    _sources = widget.sources;
    _loadSummary();
    _checkLiveStream();
  }

  Future<void> _checkLiveStream() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('live_streams')
          .select()
          .eq('id', widget.eventId)
          .maybeSingle();

      if (response != null && response['video_url'] != null && response['video_url'].toString().isNotEmpty) {
        if (mounted) {
          String? ref = response['referrer']?.toString();
          if (ref == null || ref.isEmpty) {
            final src = response['sources'];
            if (src is List && src.isNotEmpty) {
              ref = src.first['referrer']?.toString();
            }
          }
          setState(() {
            _streamUrl = response['video_url'];
            _streamReferrer = ref;
            _sources = response['sources'];
          });
        }
      }
    } catch (e) {
      debugPrint('[SportsGameDetailScreen] Error checking Supabase stream: $e');
      await handleIfUnrecoverableAuthError(e);
    }
  }

  void _playLiveStream() async {
    if (_streamUrl == null) return;

    // Show interstitial ad before navigation
    await AdService.instance.showInterstitialAd();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          url: _streamUrl!,
          title: widget.gameName ?? 'Live Stream',
          item: _summary,
          isMovie: false,
          referrer: _streamReferrer,
          allProviders: _sources?.map((s) => {
            'name': s['name']?.toString() ?? 'Source',
            'code': s['url']?.toString() ?? '',
            'referrer': s['referrer']?.toString() ?? '',
          }).toList().cast<Map<String, String>>(),
        ),
      ),
    );
  }

  Future<void> _loadSummary() async {
    try {
      final String base = (widget.baseUrl ?? caffeineApiUrl).replaceFirst(RegExp(r'/$'), '');
      final String url = '$base/sports/${widget.sport}/${widget.league}/summary/${widget.eventId}';
      debugPrint('[SportsGameDetailScreen] Fetching summary from: $url');

      final client = widget.client ?? http.Client();
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $caffeineApiKey',
        },
      );

      if (!mounted) {
        if (widget.client == null) client.close();
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _summary = data;
          if (_summary != null) {
            _summary!['media_type'] = 'live';
          }
          _isLoading = false;
        });
        debugPrint('[SportsGameDetailScreen] Successfully loaded summary.');
      } else {
        debugPrint('[SportsGameDetailScreen] Status: ${response.statusCode}');
        setState(() {
          _error = 'Failed to load summary: ${response.statusCode}';
          _isLoading = false;
        });
      }
      if (widget.client == null) client.close();
    } catch (e) {
      debugPrint('[SportsGameDetailScreen] ❌ Error loading summary: $e');
      if (mounted) {
        setState(() {
          _error = 'Error loading summary: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _loadSummary();
  }

  bool get _isCombat =>
      _summary?['header']?['league']?['slug']?.toString().contains('mma') == true ||
      _summary?['header']?['league']?['slug']?.toString().contains('ufc') == true ||
      _summary?['header']?['id']?.toString() == '600057366';

  _GameHeaderData _extractHeaderData() {
    final header = _summary?['header'];
    final competitions = header?['competitions'] as List?;

    // Improved selection for UFC/MMA: find the active fight, or default to
    // the main event (last in the list).
    dynamic competition;
    if (competitions != null && competitions.isNotEmpty) {
      if (_isCombat) {
        competition = competitions.firstWhere(
            (c) => c['status']?['type']?['state'] == 'in',
            orElse: () => null);
        competition ??= competitions.firstWhere(
            (c) => c['status']?['type']?['state'] == 'pre',
            orElse: () => null);
        competition ??= competitions.last;
      } else {
        competition = competitions.first;
      }
    }

    final competitors = competition?['competitors'] as List?;

    // MMA/UFC often doesn't have home/away; fall back to indices.
    dynamic homeTeam;
    dynamic awayTeam;
    if (competitors != null && competitors.isNotEmpty) {
      homeTeam = competitors.firstWhere((c) => c['homeAway'] == 'home', orElse: () => competitors.length > 1 ? competitors[1] : competitors[0]);
      awayTeam = competitors.firstWhere((c) => c['homeAway'] == 'away', orElse: () => competitors[0]);
    }

    // MMA/UFC scores are often irrelevant or absent — hide them.
    final homeScore = _isCombat ? null : _str(homeTeam?['score'] ?? '0');
    final awayScore = _isCombat ? null : _str(awayTeam?['score'] ?? '0');

    // Support both 'team' (NFL/NBA) and 'athlete' (UFC/MMA) structures.
    final homeName = _str(homeTeam?['team']?['displayName']) ?? _str(homeTeam?['athlete']?['displayName']) ?? 'Home';
    final awayName = _str(awayTeam?['team']?['displayName']) ?? _str(awayTeam?['athlete']?['displayName']) ?? 'Away';

    final homeLogo = _str(homeTeam?['team']?['logos']?.first?['href']) ??
        _str(homeTeam?['team']?['logo']) ??
        _str(homeTeam?['athlete']?['headshot']) ??
        _str(homeTeam?['athlete']?['flag']);
    final awayLogo = _str(awayTeam?['team']?['logos']?.first?['href']) ??
        _str(awayTeam?['team']?['logo']) ??
        _str(awayTeam?['athlete']?['headshot']) ??
        _str(awayTeam?['athlete']?['flag']);

    final state = header?['status']?['type']?['state']?.toString();
    final statusDetail = _str(header?['status']?['type']?['detail']) ?? 'Final';

    return _GameHeaderData(
      homeName: homeName,
      awayName: awayName,
      homeLogo: homeLogo,
      awayLogo: awayLogo,
      homeScore: homeScore,
      awayScore: awayScore,
      statusDetail: statusDetail,
      isLive: state == 'in',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const FullScreenLoading();
    }

    if (_error != null) {
      return FullScreenError(
        message: "This game couldn't be loaded",
        subtitle: _error!,
        onRetry: _retry,
      );
    }

    if (_summary == null) {
      return FullScreenError(
        message: 'No data available',
        onRetry: _retry,
      );
    }

    double s(double v) => ResponsiveUtils.scale(context, v);
    final header = _extractHeaderData();

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed vignette canvas — sports summaries carry no
          // photographic backdrop, so the "hero" is the scoreboard itself
          // set against the same near-black stage as the player/other
          // detail screens, instead of a stretched card list under an
          // AppBar.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [DashboardTheme.surface, DashboardTheme.canvasBlack],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: s(56), vertical: s(48)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: s(24)),
                  Row(
                    children: [
                      if (header.isLive) ...[
                        HeroBadge(
                          label: 'LIVE',
                          icon: Icons.circle,
                          color: DashboardTheme.signalRed,
                          borderColor: DashboardTheme.signalRed.withValues(alpha: 0.5),
                        ),
                        SizedBox(width: s(14)),
                      ],
                      HeroBadge(
                        label: widget.league.toUpperCase(),
                        color: Colors.white.withValues(alpha: 0.12),
                        borderColor: Colors.white24,
                      ),
                    ],
                  ),
                  SizedBox(height: s(40)),
                  Center(child: _Scoreboard(data: header, s: s)),
                  SizedBox(height: s(20)),
                  Center(
                    child: Text(
                      header.statusDetail,
                      style: DashboardTheme.heroMeta(context),
                    ),
                  ),
                  if (_streamUrl != null) ...[
                    SizedBox(height: s(36)),
                    Center(
                      child: ActionButton(
                        label: 'WATCH LIVE',
                        icon: Icons.play_arrow,
                        isPrimary: true,
                        autofocus: true,
                        onTap: _playLiveStream,
                        s: s,
                      ),
                    ),
                  ],
                  if (_isCombat) ...[
                    SizedBox(height: s(64)),
                    SectionHeader(title: 'FIGHT CARD', s: s),
                    SizedBox(height: s(24)),
                    _FightCard(summary: _summary!, s: s),
                  ],
                  if ((_summary?['winProbability'] as List?)?.isNotEmpty == true) ...[
                    SizedBox(height: s(64)),
                    SectionHeader(title: 'WIN PROBABILITY', s: s),
                    SizedBox(height: s(24)),
                    _WinProbability(summary: _summary!, header: header, s: s),
                  ],
                  if ((_summary?['plays'] as List?)?.isNotEmpty == true) ...[
                    SizedBox(height: s(64)),
                    SectionHeader(title: 'RECENT PLAYS', s: s),
                    SizedBox(height: s(24)),
                    _RecentPlays(summary: _summary!, s: s),
                  ],
                  if ((_summary?['players'] as List?)?.isNotEmpty == true) ...[
                    SizedBox(height: s(64)),
                    SectionHeader(title: 'BOXSCORE', s: s),
                    SizedBox(height: s(24)),
                    _Boxscore(summary: _summary!, s: s),
                  ],
                  SizedBox(height: s(48)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameHeaderData {
  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final String? homeScore;
  final String? awayScore;
  final String statusDetail;
  final bool isLive;

  const _GameHeaderData({
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeScore,
    required this.awayScore,
    required this.statusDetail,
    required this.isLive,
  });
}

class _Scoreboard extends StatelessWidget {
  final _GameHeaderData data;
  final double Function(double) s;

  const _Scoreboard({required this.data, required this.s});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TeamColumn(name: data.awayName, logo: data.awayLogo, score: data.awayScore, s: s),
        SizedBox(width: s(48)),
        Text('VS', style: TextStyle(color: Colors.white38, fontSize: s(28), fontWeight: FontWeight.w800, letterSpacing: 1.0)),
        SizedBox(width: s(48)),
        _TeamColumn(name: data.homeName, logo: data.homeLogo, score: data.homeScore, s: s),
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  final String name;
  final String? logo;
  final String? score;
  final double Function(double) s;

  const _TeamColumn({required this.name, required this.logo, required this.score, required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: s(120),
          height: s(120),
          padding: EdgeInsets.all(s(18)),
          decoration: BoxDecoration(
            color: DashboardTheme.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: DashboardTheme.divider),
          ),
          child: (logo != null && logo!.isNotEmpty)
              ? Image.network(logo!, errorBuilder: (c, e, s) => const Icon(Icons.sports, color: Colors.white24))
              : const Icon(Icons.sports, color: Colors.white24),
        ),
        SizedBox(height: s(16)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: s(220)),
          child: Text(
            name,
            style: TextStyle(color: Colors.white, fontSize: s(20), fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null && score != '0') ...[
          SizedBox(height: s(4)),
          Text(score!, style: TextStyle(color: Colors.white, fontSize: s(56), fontWeight: FontWeight.w900)),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(s(20)),
      decoration: BoxDecoration(
        color: DashboardTheme.surface,
        borderRadius: BorderRadius.circular(s(14)),
        border: Border.all(color: DashboardTheme.divider),
      ),
      child: child,
    );
  }
}

class _FightCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final double Function(double) s;

  const _FightCard({required this.summary, required this.s});

  @override
  Widget build(BuildContext context) {
    final competitions = summary['header']?['competitions'] as List?;
    if (competitions == null || competitions.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: competitions.reversed.map<Widget>((comp) {
          final status = _str(comp['status']?['type']?['detail']) ?? 'Scheduled';
          final isLive = comp['status']?['type']?['state'] == 'in';

          final items = comp['competitors'] as List?;
          if (items == null || items.length < 2) return const SizedBox.shrink();

          final home = items[0];
          final away = items[1];

          final homeName = _str(home['athlete']?['displayName']) ?? 'TBD';
          final awayName = _str(away['athlete']?['displayName']) ?? 'TBD';
          final homeWon = home['winner'] == true;
          final awayWon = away['winner'] == true;

          return Container(
            margin: EdgeInsets.only(bottom: s(12)),
            padding: EdgeInsets.all(s(14)),
            decoration: BoxDecoration(
              color: DashboardTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(s(10)),
              border: Border.all(color: DashboardTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(homeName, style: TextStyle(color: homeWon ? DashboardTheme.successGreen : Colors.white70, fontWeight: FontWeight.bold, fontSize: s(15))),
                          if (homeWon) ...[
                            SizedBox(width: s(6)),
                            Icon(Icons.check_circle, color: DashboardTheme.successGreen, size: s(14)),
                          ],
                        ],
                      ),
                      SizedBox(height: s(2)),
                      Text('vs', style: TextStyle(color: Colors.white24, fontSize: s(11))),
                      SizedBox(height: s(2)),
                      Row(
                        children: [
                          Text(awayName, style: TextStyle(color: awayWon ? DashboardTheme.successGreen : Colors.white70, fontWeight: FontWeight.bold, fontSize: s(15))),
                          if (awayWon) ...[
                            SizedBox(width: s(6)),
                            Icon(Icons.check_circle, color: DashboardTheme.successGreen, size: s(14)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: s(8)),
                HeroBadge(
                  label: status,
                  color: isLive ? DashboardTheme.signalRed : Colors.white.withValues(alpha: 0.08),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WinProbability extends StatelessWidget {
  final Map<String, dynamic> summary;
  final _GameHeaderData header;
  final double Function(double) s;

  const _WinProbability({required this.summary, required this.header, required this.s});

  @override
  Widget build(BuildContext context) {
    final winProb = summary['winProbability'] as List?;
    if (winProb == null || winProb.isEmpty) return const SizedBox.shrink();

    final latest = winProb.last;
    final homeProb = (latest['homeWinPercentage'] as num? ?? 0.0) * 100;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(s(12)),
            child: Stack(
              children: [
                Container(height: s(20), color: Colors.white.withValues(alpha: 0.08)),
                FractionallySizedBox(
                  widthFactor: (homeProb / 100).clamp(0.0, 1.0),
                  child: Container(height: s(20), color: Colors.white),
                ),
              ],
            ),
          ),
          SizedBox(height: s(12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${header.awayName} ${(100 - homeProb).toStringAsFixed(1)}%', style: TextStyle(color: Colors.white70, fontSize: s(15))),
              Text('${header.homeName} ${homeProb.toStringAsFixed(1)}%', style: TextStyle(color: Colors.white70, fontSize: s(15))),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentPlays extends StatelessWidget {
  final Map<String, dynamic> summary;
  final double Function(double) s;

  const _RecentPlays({required this.summary, required this.s});

  @override
  Widget build(BuildContext context) {
    final plays = summary['plays'] as List?;
    if (plays == null || plays.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: plays.reversed.take(5).map<Widget>((play) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: s(6)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: s(52),
                  child: Text(play['clock']?['displayValue'] ?? '', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: s(14))),
                ),
                SizedBox(width: s(12)),
                Expanded(child: Text(play['text'] ?? '', style: TextStyle(color: Colors.white70, fontSize: s(14)))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Boxscore extends StatelessWidget {
  final Map<String, dynamic> summary;
  final double Function(double) s;

  const _Boxscore({required this.summary, required this.s});

  @override
  Widget build(BuildContext context) {
    final players = summary['players'] as List?;
    if (players == null || players.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: players.map<Widget>((teamBox) {
          final teamName = teamBox['team']?['displayName'] ?? 'Team';
          final statistics = teamBox['statistics'] as List?;

          // Robustly find athletes across any statistic category.
          List<dynamic> athletes = [];
          if (statistics != null) {
            for (var stat in statistics) {
              final statAthletes = stat['athletes'] as List?;
              if (statAthletes != null && statAthletes.isNotEmpty) {
                athletes = statAthletes;
                break;
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: s(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(teamName, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: s(16))),
                SizedBox(height: s(10)),
                if (athletes.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: s(8)),
                    child: Text('No player stats available', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: s(14))),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: s(20),
                      headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.04)),
                      columns: const [
                        DataColumn(label: Text('Player', style: TextStyle(color: Colors.white54))),
                        DataColumn(label: Text('PTS', style: TextStyle(color: Colors.white54))),
                        DataColumn(label: Text('REB', style: TextStyle(color: Colors.white54))),
                        DataColumn(label: Text('AST', style: TextStyle(color: Colors.white54))),
                      ],
                      rows: athletes.map((athlete) {
                        final stats = athlete['stats'] as List?;
                        final name = athlete['athlete']?['displayName'] ?? 'Unknown';

                        String getStat(int index) {
                          if (stats == null || index >= stats.length) return '0';
                          return stats[index]?.toString() ?? '0';
                        }

                        return DataRow(cells: [
                          DataCell(Text(name, style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(stats?.length != null ? stats!.length - 1 : 0), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(7), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(8), style: const TextStyle(color: Colors.white))),
                        ]);
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
