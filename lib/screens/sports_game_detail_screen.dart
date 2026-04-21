import 'dart:convert';
import 'package:caffeine_tv/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
import 'package:caffeine_tv/services/ad_service.dart';

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
      final String base = widget.baseUrl ?? caffeineApiUrl;
      final String url = '${base}sports/${widget.sport}/${widget.league}/summary/${widget.eventId}';
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

  bool get _isCombat =>
      _summary?['header']?['league']?['slug']?.toString().contains('mma') == true ||
      _summary?['header']?['league']?['slug']?.toString().contains('ufc') == true ||
      _summary?['header']?['id']?.toString() == '600057366';

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
          _buildHeader(),
          if (_isCombat) _buildFightCard(),
          _buildWinProbability(),
          _buildRecentPlays(),
          _buildBoxscore(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final header = _summary?['header'];
    final competitions = header?['competitions'] as List?;
    
    // Improved selection for UFC/MMA: Find the active fight or default to the Main Event (last)
    dynamic competition;
    if (competitions != null && competitions.isNotEmpty) {
      if (_isCombat) {
        // 1. Try to find the currently active fight ('in' status)
        competition = competitions.firstWhere(
            (c) => c['status']?['type']?['state'] == 'in',
            orElse: () => null);

        // 2. If no active fight, try to find the next upcoming fight ('pre' status)
        competition ??= competitions.firstWhere(
            (c) => c['status']?['type']?['state'] == 'pre',
            orElse: () => null);

        // 3. Fallback to the Main Event (usually the last in the list)
        competition ??= competitions.last;
      } else {
        competition = competitions.first;
      }
    }

    final competitors = competition?['competitors'] as List?;
    
    // Safely find home and away teams using orElse to avoid StateError
    // MMA/UFC often doesn't have home/away; fallback to indices
    dynamic homeTeam;
    dynamic awayTeam;
    
    if (competitors != null && competitors.isNotEmpty) {
      homeTeam = competitors.firstWhere((c) => c['homeAway'] == 'home', orElse: () => competitors.length > 1 ? competitors[1] : competitors[0]);
      awayTeam = competitors.firstWhere((c) => c['homeAway'] == 'away', orElse: () => competitors[0]);
    }

    // Safely extract values as strings to avoid TypeErrors if the API returns an object
    String? getStringValue(dynamic val) {
      if (val == null) return null;
      if (val is String) return val;
      if (val is Map && val['href'] != null) return val['href'].toString();
      return val.toString();
    }

    // MMA/UFC Header: Do not show scores as they are often irrelevant or not provided natively
    final isCombat = header?['league']?['slug']?.toString().contains('mma') == true || 
                    header?['league']?['slug']?.toString().contains('ufc') == true ||
                    header?['id']?.toString() == '600057366'; // UFC Event ID constant if needed
                    
    final homeScore = isCombat ? null : (homeTeam?['score'] ?? '0');
    final awayScore = isCombat ? null : (awayTeam?['score'] ?? '0');
    
    // Support both 'team' (NFL/NBA) and 'athlete' (UFC/MMA) structures
    // Use getStringValue to prevent TypeErrors if names are nested objects
    final homeName = getStringValue(homeTeam?['team']?['displayName']) ?? 
                    getStringValue(homeTeam?['athlete']?['displayName']) ?? 
                    'Home';
    final awayName = getStringValue(awayTeam?['team']?['displayName']) ?? 
                    getStringValue(awayTeam?['athlete']?['displayName']) ?? 
                    'Away';
    
    // Core API structure for logos is often team.logo or team.logos
    // For athletes, it can be athlete.headshot or athlete.flag

    final homeLogo = getStringValue(homeTeam?['team']?['logos']?.first?['href']) ?? 
                    getStringValue(homeTeam?['team']?['logo']) ?? 
                    getStringValue(homeTeam?['athlete']?['headshot']) ??
                    getStringValue(homeTeam?['athlete']?['flag']);
                    
    final awayLogo = getStringValue(awayTeam?['team']?['logos']?.first?['href']) ?? 
                    getStringValue(awayTeam?['team']?['logo']) ?? 
                    getStringValue(awayTeam?['athlete']?['headshot']) ??
                    getStringValue(awayTeam?['athlete']?['flag']);

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
              _buildTeamHeader(awayName, awayLogo, awayScore?.toString()),
              const Text('vs', style: TextStyle(color: Colors.white54, fontSize: 24)),
              _buildTeamHeader(homeName, homeLogo, homeScore?.toString()),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            getStringValue(header?['status']?['type']?['detail']) ?? 'Final',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          if (_streamUrl != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              autofocus: true, // Should be easy to select when arriving
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
              ),
              onPressed: _playLiveStream,
              icon: const Icon(Icons.play_arrow, size: 32),
              label: const Text(
                'WATCH LIVE', 
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamHeader(String name, String? logo, String? score) {
    return Column(
      children: [
        if (logo != null && logo.isNotEmpty)
          Image.network(logo, height: 64, width: 64, errorBuilder: (c, e, s) => const Icon(Icons.sports, size: 64))
        else
          const Icon(Icons.sports, size: 64, color: Colors.white24),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        if (score != null && score != '0')
          Text(score, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.blue)),
      ],
    );
  }

  Widget _buildFightCard() {
    final competitions = _summary?['header']?['competitions'] as List?;
    if (competitions == null || competitions.isEmpty) return const SizedBox.shrink();

    String? getStringValue(dynamic val) {
      if (val == null) return null;
      if (val is String) return val;
      if (val is Map && val['href'] != null) return val['href'].toString();
      return val.toString();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fight Card', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...competitions.reversed.map((comp) {
            final status = getStringValue(comp['status']?['type']?['detail']) ?? 'Scheduled';

            final items = comp['competitors'] as List?;
            if (items == null || items.length < 2) return const SizedBox.shrink();

            final home = items[0];
            final away = items[1];

            final homeName = getStringValue(home['athlete']?['displayName']) ?? 'TBD';
            final awayName = getStringValue(away['athlete']?['displayName']) ?? 'TBD';
            
            final homeResult = home['winner'] == true ? 'WIN' : '';
            final awayResult = away['winner'] == true ? 'WIN' : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(homeName, style: TextStyle(color: homeResult == 'WIN' ? Colors.green : Colors.white70, fontWeight: FontWeight.bold)),
                            if (homeResult == 'WIN') const Icon(Icons.check_circle, color: Colors.green, size: 14),
                          ],
                        ),
                        const Text('vs', style: TextStyle(color: Colors.white24, fontSize: 10)),
                        Row(
                          children: [
                            Text(awayName, style: TextStyle(color: awayResult == 'WIN' ? Colors.green : Colors.white70, fontWeight: FontWeight.bold)),
                            if (awayResult == 'WIN') const Icon(Icons.check_circle, color: Colors.green, size: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: status.contains('Final') ? Colors.black45 : Colors.red[900],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
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
