import 'dart:convert';
import 'package:caffeine_tv/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/screens/player_screen.dart';

class SportsGameDetailScreen extends StatefulWidget {
  final String sport;
  final String league;
  final String eventId;
  final String? gameName;
  final String? baseUrl;
  final http.Client? client;

  const SportsGameDetailScreen({
    super.key,
    required this.sport,
    required this.league,
    required this.eventId,
    this.gameName,
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

  @override
  void initState() {
    super.initState();
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
          setState(() {
            _streamUrl = response['video_url'];
            _streamReferrer = response['referrer'];
          });
        }
      }
    } catch (e) {
      debugPrint('[SportsGameDetailScreen] Error checking Supabase stream: $e');
    }
  }

  void _playLiveStream() {
    if (_streamUrl == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          url: _streamUrl!,
          title: widget.gameName ?? 'Live Stream',
          item: _summary,
          isMovie: false,
          referrer: _streamReferrer,
        ),
      ),
    );
  }

  Future<void> _loadSummary() async {
    try {
      final String base = widget.baseUrl ?? caffeineApiUrl;
      final String url = '$base/sports/${widget.sport}/${widget.league}/summary/${widget.eventId}';
      debugPrint('[SportsGameDetailScreen] Fetching summary from: $url');
      
      final client = widget.client ?? http.Client();
      final response = await client.get(Uri.parse(url));

      if (!mounted) {
        if (widget.client == null) client.close();
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _summary = data;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadSummary();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_summary == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No data available', style: TextStyle(color: Colors.white))),
      );
    }

    // Wrap sections in Focus widgets for TV navigation
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.gameName ?? 'Game Details'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          Focus(child: _buildHeader()),
          Focus(child: _buildWinProbability()),
          Focus(child: _buildRecentPlays()),
          Focus(child: _buildBoxscore()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final header = _summary?['header'];
    final competitions = header?['competitions'] as List?;
    final competition = competitions?.first;
    final competitors = competition?['competitors'] as List?;
    
    // Correcting score retrieval to use header data
    final homeTeam = competitors?.firstWhere((c) => c['homeAway'] == 'home');
    final awayTeam = competitors?.firstWhere((c) => c['homeAway'] == 'away');
    
    final homeScore = homeTeam?['score'] ?? '0';
    final awayScore = awayTeam?['score'] ?? '0';
    
    final homeName = homeTeam?['team']?['displayName'] ?? 'Home';
    final awayName = awayTeam?['team']?['displayName'] ?? 'Away';
    final homeLogo = homeTeam?['team']?['logos']?.first?['href'];
    final awayLogo = awayTeam?['team']?['logos']?.first?['href'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey[900]!, Colors.black],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTeamHeader(awayName, awayLogo, awayScore),
              const Text('vs', style: TextStyle(color: Colors.white54, fontSize: 24)),
              _buildTeamHeader(homeName, homeLogo, homeScore),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            header?['status']?['type']?['detail'] ?? 'Final',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          if (_streamUrl != null) ...[
            const SizedBox(height: 24),
            Focus(
              child: Builder(
                builder: (context) {
                  final isFocused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFocused ? Colors.red : Colors.grey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _playLiveStream,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('WATCH LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
                  );
                }
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamHeader(String name, String? logo, String score) {
    return Column(
      children: [
        if (logo != null)
          Image.network(logo, height: 64, width: 64, errorBuilder: (c, e, s) => const Icon(Icons.sports, size: 64)),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(score, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.blue)),
      ],
    );
  }

  Widget _buildWinProbability() {
    final winProb = _summary?['winProbability'] as List?;
    if (winProb == null || winProb.isEmpty) return const SizedBox.shrink();

    final latest = winProb.last;
    final homeProb = (latest['homeWinPercentage'] as num? ?? 0.0) * 100;
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Win Probability', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(height: 24, decoration: BoxDecoration(color: Colors.blue[900], borderRadius: BorderRadius.circular(12))),
              FractionallySizedBox(
                widthFactor: homeProb / 100,
                child: Container(height: 24, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Away ${(100 - homeProb).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70)),
              Text('Home ${homeProb.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentPlays() {
    final plays = _summary?['plays'] as List?;
    if (plays == null || plays.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Plays', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...plays.reversed.take(5).map((play) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(play['clock']?['displayValue'] ?? '', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Expanded(child: Text(play['text'] ?? '', style: const TextStyle(color: Colors.white70))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildBoxscore() {
    final players = _summary?['players'] as List?;
    if (players == null || players.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Boxscore', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...players.map((teamBox) {
            final teamName = teamBox['team']?['displayName'] ?? 'Team';
            final statistics = teamBox['statistics'] as List?;
            
            // Robustly find athletes across any statistic category
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(teamName, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (athletes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No player stats available', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('Player', style: TextStyle(color: Colors.white70))),
                        DataColumn(label: Text('PTS', style: TextStyle(color: Colors.white70))),
                        DataColumn(label: Text('REB', style: TextStyle(color: Colors.white70))),
                        DataColumn(label: Text('AST', style: TextStyle(color: Colors.white70))),
                      ],
                      rows: athletes.map((athlete) {
                        final stats = athlete['stats'] as List?;
                        final name = athlete['athlete']?['displayName'] ?? 'Unknown';
                        
                        // Safely get stats with fallback to '0'
                        String getStat(int index) {
                          if (stats == null || index >= stats.length) return '0';
                          return stats[index]?.toString() ?? '0';
                        }

                        // Adjusting indices based on common ESPN API structure for NBA
                        // Usually: 0: MIN, 7: REB, 8: AST, 11: PTS (but varies)
                        // For simplicity in display, we take common positions or search
                        return DataRow(cells: [
                          DataCell(Text(name, style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(stats?.length != null ? stats!.length - 1 : 0), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(7), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(getStat(8), style: const TextStyle(color: Colors.white))),
                        ]);
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            );
          }),
        ],
      ),
    );
  }
}
