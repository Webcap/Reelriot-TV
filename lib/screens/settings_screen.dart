import 'dart:async';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../env.dart';
import 'update_screen.dart';
import '../utils/avatar_utils.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onMounted;
  const SettingsScreen({super.key, this.onMounted});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  bool _loading = false;
  String? _name;
  String? _email;
  int _movieWatchTimeMs = 0;
  int _tvWatchTimeMs = 0;
  late String _currentLanguage;
  String? _avatar;
  late String _currentRegion;
  late String _currentAudioLanguage;

  final List<Map<String, String>> _languages = [
    {'name': 'English', 'code': 'en'},
    {'name': 'Spanish', 'code': 'es'},
    {'name': 'French', 'code': 'fr'},
    {'name': 'German', 'code': 'de'},
    {'name': 'Portuguese', 'code': 'pt'},
    {'name': 'Italian', 'code': 'it'},
    {'name': 'Japanese', 'code': 'ja'},
    {'name': 'Korean', 'code': 'ko'},
    {'name': 'Chinese', 'code': 'zh'},
  ];

  final List<Map<String, String>> _regions = [
    {'name': 'United States', 'code': 'US'},
    {'name': 'Spain', 'code': 'ES'},
    {'name': 'France', 'code': 'FR'},
    {'name': 'Germany', 'code': 'DE'},
    {'name': 'Mexico', 'code': 'MX'},
    {'name': 'Brazil', 'code': 'BR'},
    {'name': 'Italy', 'code': 'IT'},
    {'name': 'Japan', 'code': 'JP'},
    {'name': 'South Korea', 'code': 'KR'},
    {'name': 'United Kingdom', 'code': 'GB'},
  ];

  Stream<Map<String, dynamic>?>? _profileStream;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _currentLanguage = _settings.language;
    _currentRegion = _settings.region;
    _currentAudioLanguage = _settings.defaultAudioLanguage;
    _initProfileStream();
    _loadUserData();
    widget.onMounted?.call();

    // Auth listener for basic state
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.signedOut) {
        _initProfileStream();
        _loadUserData();
      }
    });
  }

  void _initProfileStream() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _profileStream = null);
      return;
    }

    setState(() {
      _profileStream = Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', user.id)
          .limit(1)
          .map((data) {
            if (data.isNotEmpty) {
              debugPrint('[TV Avatar Sync] 🟢 Received real-time update: profile_id=${data.first['profile_id']}');
              return data.first;
            }
            return null;
          });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    setState(() => _loading = true);

    try {
      final userResponse = await Supabase.instance.client.auth.getUser();
      final user = userResponse.user;
      if (user == null) return;
      _email = user.email;

      // 1. Fetch profile name (Initial fetch, rest is handled by stream)
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .limit(1);
      
      if (mounted) {
        setState(() {
          final profileData = profileRes.isNotEmpty ? profileRes[0] : null;
          _name = profileData?['name'] as String?;
          
          // Initial avatar resolution
          _avatar = user.userMetadata?['avatar']?.toString() ?? 
                    user.userMetadata?['avatar_url']?.toString() ??
                    profileData?['profile_id']?.toString();
        });
      }

      // 2. Fetch watch history from both completed and continue watching updated in the last 14 days
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14)).toUtc().toIso8601String();
      
      final completedRes = await Supabase.instance.client
          .from('completed_watch_history')
          .select('time_watched_ms, media_type')
          .eq('user_id', user.id)
          .gte('updated_at', twoWeeksAgo);

      final continueRes = await Supabase.instance.client
          .from('continue_watching_history')
          .select('elapsed_ms, media_type')
          .eq('user_id', user.id)
          .gte('updated_at', twoWeeksAgo);

      int movieTime = 0;
      int tvTime = 0;

      for (var row in (completedRes as List)) {
        final ms = row['time_watched_ms'] as int? ?? 0;
        if (row['media_type'] == 'movie') {
          movieTime += ms;
        } else {
          tvTime += ms;
        }
      }

      for (var row in (continueRes as List)) {
        final ms = row['elapsed_ms'] as int? ?? 0;
        if (row['media_type'] == 'movie') {
          movieTime += ms;
        } else {
          tvTime += ms;
        }
      }

      if (mounted) {
        setState(() {
          _movieWatchTimeMs = movieTime;
          _tvWatchTimeMs = tvTime;
        });
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
      return '${hours}h${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
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
                StreamBuilder<Map<String, dynamic>?>(
                  stream: _profileStream,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    final dbProfileId = data?['profile_id']?.toString();
                    
                    // Smart fallback: If DB says 0 or null, check if _avatar (from metadata) has a better value
                    final avatarId = (dbProfileId != null && dbProfileId != '0') 
                        ? dbProfileId 
                        : (_avatar ?? '0');
                        
                    final name = data?['name']?.toString() ?? _name ?? 'User';

                    return Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.symmetric(horizontal: 48),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white24, width: 2),
                              image: DecorationImage(
                                image: NetworkImage(AvatarUtils.getAvatarUrl(avatarId)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            name,
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
                    );
                  }
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
                          subtitle: '(Last 2 weeks)',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: 'TV Watch Time',
                          value: _formatDuration(_tvWatchTimeMs),
                          icon: Icons.tv_rounded,
                          subtitle: '(Last 2 weeks)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Language Section
                Text(
                  'Language',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _languages.map((lang) {
                      final isSelected = _currentLanguage == lang['code'];
                      return Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.select)) {
                            _updateLanguage(lang['code']!);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return ChoiceChip(
                            label: Text(lang['name']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) _updateLanguage(lang['code']!);
                            },
                            backgroundColor: focused ? Colors.white24 : Colors.transparent,
                            selectedColor: const Color(0xFFDC2626),
                            labelStyle: TextStyle(
                              color: isSelected || focused ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                // Region Section
                Text(
                  'Watch Region',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _regions.map((reg) {
                      final isSelected = _currentRegion == reg['code'];
                      return Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.select)) {
                            _updateRegion(reg['code']!);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return ChoiceChip(
                            label: Text(reg['name']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) _updateRegion(reg['code']!);
                            },
                            backgroundColor: focused ? Colors.white24 : Colors.transparent,
                            selectedColor: const Color(0xFFDC2626),
                            labelStyle: TextStyle(
                              color: isSelected || focused ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                // Audio Language Section
                Text(
                  'Default Audio Language',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _languages.map((lang) {
                      final isSelected = _currentAudioLanguage == lang['code'];
                      return Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.select)) {
                            _updateAudioLanguage(lang['code']!);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return ChoiceChip(
                            label: Text(lang['name']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) _updateAudioLanguage(lang['code']!);
                            },
                            backgroundColor:
                                focused ? Colors.white24 : Colors.transparent,
                            selectedColor: const Color(0xFFDC2626),
                            labelStyle: TextStyle(
                              color: isSelected || focused
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                // Subtitles Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.select)) {
                        _toggleExternalSubtitles(!_settings.useExternalSubtitles);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      final enabled = _settings.useExternalSubtitles;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: focused ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: focused ? Colors.white38 : Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              enabled ? Icons.subtitles : Icons.subtitles_off,
                              color: enabled ? const Color(0xFFDC2626) : Colors.white24,
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'External Subtitles (OpenSubtitles)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Automatically download & select best available tracks',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: enabled,
                              onChanged: (val) => _toggleExternalSubtitles(val),
                              activeThumbColor: const Color(0xFFDC2626),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              // Update Section
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select)) {
                    _checkForUpdate(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    onPressed: () => _checkForUpdate(context),
                    icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.system_update_alt),
                    label: const Text('Check for update'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : Colors.white10,
                      foregroundColor: focused ? Colors.black : Colors.white,
                      side: focused ? const BorderSide(color: Colors.white, width: 2) : const BorderSide(color: Colors.white12),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select)) {
                    _signOut(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                      foregroundColor: focused ? Colors.black : Colors.white,
                      side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  );
                }),
              ),
            ] else
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select)) {
                    Navigator.of(context).pushNamed('/pairing');
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/pairing'),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                      foregroundColor: focused ? Colors.black : Colors.white,
                      side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final api = ApiService();
      await api.loadConfig();
      
      final info = await UpdateService().checkForUpdate(
        caffeineApiUrl,
        env: environment,
        apiKey: caffeineApiKey,
      );

      if (!mounted) return;

      if (info.isUpdateAvailable) {
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: info)),
        );
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App is up to date!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _signOut(BuildContext context) {
    Supabase.instance.client.auth.signOut();
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Future<void> _updateLanguage(String code) async {
    await _settings.setLanguage(code);
    setState(() {
      _currentLanguage = code;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Language updated to ${_languages.firstWhere((l) => l['code'] == code)['name']}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updateRegion(String code) async {
    await _settings.setRegion(code);
    setState(() {
      _currentRegion = code;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Region updated to ${_regions.firstWhere((r) => r['code'] == code)['name']}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updateAudioLanguage(String code) async {
    await _settings.setDefaultAudioLanguage(code);
    setState(() {
      _currentAudioLanguage = code;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Audio language updated to ${_languages.firstWhere((l) => l['code'] == code)['name']}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleExternalSubtitles(bool value) async {
    await _settings.setUseExternalSubtitles(value);
    setState(() {}); // Refresh local state
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External subtitles ${value ? "enabled" : "disabled"}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? subtitle;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.subtitle,
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
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
