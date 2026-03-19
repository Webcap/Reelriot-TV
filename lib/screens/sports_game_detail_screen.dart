import 'dart:convert';
import 'package:caffeine_tv/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SportsGameDetailScreen extends StatefulWidget {
  final String sport;
  final String league;
  final String eventId;
  final String? gameName;

  const SportsGameDetailScreen({
    super.key,
    required this.sport,
    required this.league,
    required this.eventId,
    this.gameName,
  });

  @override
  State<SportsGameDetailScreen> createState() => _SportsGameDetailScreenState();
}

class _SportsGameDetailScreenState extends State<SportsGameDetailScreen> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = caffeineApiUrl.endsWith('/') ? caffeineApiUrl : '$caffeineApiUrl/';
      final url = '${base}sports/${widget.sport}/${widget.league}/summary/${widget.eventId}';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw 'Failed to load game details: ${res.statusCode}';
      }
      if (mounted) {
        setState(() {
          _summary = jsonDecode(res.body);
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

  double _s(BuildContext context, double v) =>
      (v * MediaQuery.of(context).size.width) / 1920;

  @override
  Widget build(BuildContext context) {
    final s = (double v) => _s(context, v);

    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              Text('Could not load game stats',
                  style: TextStyle(color: Colors.white54, fontSize: s(28))),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadSummary,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final boxscore = _summary?['boxscore'];
    final teams = boxscore?['teams'] as List<dynamic>? ?? [];
    if (teams.length < 2) {
       return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Game data unavailable', style: TextStyle(color: Colors.white54))),
      );
    }

    final awayTeam = teams[0];
    final homeTeam = teams[1];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(s(48)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(s, awayTeam, homeTeam),
            SizedBox(height: s(40)),
            _buildTeamStats(s, awayTeam, homeTeam),
            SizedBox(height: s(40)),
            _buildBoxscore(s, boxscore),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double Function(double) s, dynamic away, dynamic home) {
    final awayData = away['team'];
    final homeData = home['team'];
    final awayScore = away['statistics']?.firstWhere((st) => st['name'] == 'points', orElse: () => null)?['displayValue'] ?? '0';
    final homeScore = home['statistics']?.firstWhere((st) => st['name'] == 'points', orElse: () => null)?['displayValue'] ?? '0';

    final headerStatus = _summary?['header']?['competitions']?[0]?['status']?['type']?['detail'] ?? 'Final';

    return Container(
      padding: EdgeInsets.all(s(32)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(s(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTeamHeader(s, awayData, awayScore, isAway: true),
          Column(
            children: [
              Text(headerStatus, style: TextStyle(color: Colors.white38, fontSize: s(24), fontWeight: FontWeight.bold)),
              SizedBox(height: s(8)),
              Text('VS', style: TextStyle(color: Colors.white12, fontSize: s(48), fontWeight: FontWeight.w900)),
            ],
          ),
          _buildTeamHeader(s, homeData, homeScore, isAway: false),
        ],
      ),
    );
  }

  Widget _buildTeamHeader(double Function(double) s, dynamic team, String score, {bool isAway = true}) {
    return Column(
      children: [
        Image.network(team['logo'] ?? '', width: s(120), height: s(120), errorBuilder: (_, __, ___) => Icon(Icons.sports_basketball, size: s(80), color: Colors.white24)),
        SizedBox(height: s(16)),
        Text(team['displayName'] ?? '', style: TextStyle(color: Colors.white, fontSize: s(32), fontWeight: FontWeight.bold)),
        Text(team['abbreviation'] ?? '', style: TextStyle(color: Colors.white54, fontSize: s(24))),
        SizedBox(height: s(16)),
        Text(score, style: TextStyle(color: Colors.white, fontSize: s(64), fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildTeamStats(double Function(double) s, dynamic away, dynamic home) {
    final awayStats = (away['statistics'] as List<dynamic>? ?? []);
    final homeStats = (home['statistics'] as List<dynamic>? ?? []);

    final statsToDisplay = [
      {'label': 'FG%', 'key': 'fieldGoalPct'},
      {'label': '3PT%', 'key': 'threePointFieldGoalPct'},
      {'label': 'FT%', 'key': 'freeThrowPct'},
      {'label': 'REB', 'key': 'totalRebounds'},
      {'label': 'AST', 'key': 'assists'},
      {'label': 'STL', 'key': 'steals'},
      {'label': 'BLK', 'key': 'blocks'},
      {'label': 'TO', 'key': 'turnovers'},
    ];

    return Container(
      padding: EdgeInsets.all(s(32)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(s(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Team Comparison', style: TextStyle(color: Colors.white, fontSize: s(32), fontWeight: FontWeight.bold)),
          SizedBox(height: s(24)),
          ...statsToDisplay.map((stat) {
            final awayVal = awayStats.firstWhere((s) => s['name'] == stat['key'], orElse: () => null)?['displayValue'] ?? '-';
            final homeVal = homeStats.firstWhere((s) => s['name'] == stat['key'], orElse: () => null)?['displayValue'] ?? '-';

            return Padding(
              padding: EdgeInsets.symmetric(vertical: s(8)),
              child: Row(
                children: [
                  Expanded(child: Text(awayVal, textAlign: TextAlign.start, style: TextStyle(color: Colors.white70, fontSize: s(24)))),
                  Expanded(child: Text(stat['label']!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: s(20)))),
                  Expanded(child: Text(homeVal, textAlign: TextAlign.end, style: TextStyle(color: Colors.white70, fontSize: s(24)))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBoxscore(double Function(double) s, dynamic boxscore) {
    final playersData = boxscore?['players'] as List<dynamic>? ?? [];
    if (playersData.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Boxscore', style: TextStyle(color: Colors.white, fontSize: s(32), fontWeight: FontWeight.bold)),
        SizedBox(height: s(24)),
        ...playersData.map((teamBox) => _buildTeamBoxscore(s, teamBox)),
      ],
    );
  }

  Widget _buildTeamBoxscore(double Function(double) s, dynamic teamBox) {
    final team = teamBox['team'];
    final statsList = teamBox['statistics'] as List<dynamic>? ?? [];
    if (statsList.isEmpty) return const SizedBox();

    final headers = (statsList.first['labels'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final athletes = statsList.first['athletes'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: s(16)),
          child: Row(
            children: [
              Image.network(team['logo'] ?? '', width: s(40), height: s(40), errorBuilder: (_, __, ___) => const Icon(Icons.sports, color: Colors.white24)),
              SizedBox(width: s(16)),
              Text(team['displayName'] ?? '', style: TextStyle(color: Colors.white70, fontSize: s(28), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: s(24),
            headingRowHeight: s(40),
            dataRowMinHeight: s(40),
            dataRowMaxHeight: s(48),
            columns: [
              DataColumn(label: Text('Athlete', style: TextStyle(color: Colors.white38, fontSize: s(18)))),
              ...headers.map((h) => DataColumn(label: Text(h, style: TextStyle(color: Colors.white38, fontSize: s(18))))),
            ],
            rows: athletes.map((a) {
              final athlete = a['athlete'];
              final stats = a['stats'] as List<dynamic>? ?? [];
              return DataRow(cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (athlete['headshot'] != null)
                        Image.network(athlete['headshot']['href'], width: s(32), height: s(32), errorBuilder: (_, __, ___) => const SizedBox()),
                      SizedBox(width: s(8)),
                      Text(athlete['shortName'] ?? '', style: TextStyle(color: Colors.white70, fontSize: s(20))),
                    ],
                  ),
                ),
                ...stats.map((st) => DataCell(Text(st.toString(), style: TextStyle(color: Colors.white54, fontSize: s(18))))),
              ]);
            }).toList(),
          ),
        ),
        SizedBox(height: s(32)),
      ],
    );
  }
}
