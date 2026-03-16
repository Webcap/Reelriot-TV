import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = false;
  String? _name;
  String? _email;
  int _movieWatchTimeMs = 0;
  int _tvWatchTimeMs = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return;

    setState(() => _loading = true);

    try {
      final user = session.user;
      _email = user.email;

      // 1. Fetch profile name
      final profileRes = await _supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _name = profileRes?['name'] as String?;
        });
      }

      // 2. Fetch watch history and aggregate time
      final historyRes = await _supabase
          .from('watch_history')
          .select('movies, tv_shows')
          .eq('user_id', user.id)
          .maybeSingle();

      if (historyRes != null) {
        int movieTime = 0;
        final movies = historyRes['movies'] as List<dynamic>? ?? [];
        for (var m in movies) {
          if (m is Map && m['elapsed'] != null) {
            movieTime += (m['elapsed'] as num).toInt();
          }
        }

        int tvTime = 0;
        final tvShows = historyRes['tv_shows'] as List<dynamic>? ?? [];
        for (var t in tvShows) {
          if (t is Map && t['elapsed'] != null) {
            tvTime += (t['elapsed'] as num).toInt();
          }
        }

        if (mounted) {
          setState(() {
            _movieWatchTimeMs = movieTime;
            _tvWatchTimeMs = tvTime;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading settings data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '0m';
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _supabase.auth.currentSession;
    final isSignedIn = session != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            if (isSignedIn) ...[
              if (_loading)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                // Profile Section
                Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: Color(0xFFDC2626),
                        child: Icon(Icons.person, size: 48, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _name ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _email ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Stats Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Movie Watch Time',
                          value: _formatDuration(_movieWatchTimeMs),
                          icon: Icons.movie_outlined,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: 'TV Watch Time',
                          value: _formatDuration(_tvWatchTimeMs),
                          icon: Icons.tv_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 48),
              Builder(builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.select)) {
                      _signOut(context);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ElevatedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                      foregroundColor: focused ? Colors.black : Colors.white,
                      side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                );
              }),
            ] else
              Builder(builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.select)) {
                      Navigator.of(context).pushNamed('/pairing');
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/pairing'),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                      foregroundColor: focused ? Colors.black : Colors.white,
                      side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _signOut(BuildContext context) {
    _supabase.auth.signOut();
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
