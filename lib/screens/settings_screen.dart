import 'dart:async';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../env.dart';
import 'update_screen.dart';
import '../utils/avatar_utils.dart';
import '../utils/responsive_utils.dart';

enum _SettingsCategory { account, playback, general, about }

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onMounted;
  const SettingsScreen({super.key, this.onMounted});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final FocusNode _sidebarFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  _SettingsCategory _selectedCategory = _SettingsCategory.account;
  bool _loading = false;
  String? _name;
  String? _email;
  int _movieWatchTimeMs = 0;
  int _tvWatchTimeMs = 0;
  late String _currentLanguage;
  String? _avatar;
  late String _currentRegion;
  late String _currentAudioLanguage;

  void requestFocus() {
    _sidebarFocusNode.requestFocus();
  }

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
    _sidebarFocusNode.dispose();
    _contentFocusNode.dispose();
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
    double s(double v) => ResponsiveUtils.scale(context, v);

    if (!isSignedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_outlined, color: Colors.white24, size: s(120)),
            SizedBox(height: s(32)),
            Text(
              'Settings',
              style: TextStyle(color: Colors.white, fontSize: s(48), fontWeight: FontWeight.bold),
            ),
            SizedBox(height: s(16)),
            Text(
              'Sign in to manage your account and preferences',
              style: TextStyle(color: Colors.white54, fontSize: s(24)),
            ),
            SizedBox(height: s(48)),
            LongPressFocus(
              focusNode: _sidebarFocusNode,
              onTap: () => Navigator.of(context).pushNamed('/pairing'),
              child: Builder(builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: s(48), vertical: s(24)),
                  decoration: BoxDecoration(
                    color: focused ? Colors.white : const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(s(12)),
                    border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, color: focused ? Colors.black : Colors.white, size: s(28)),
                      SizedBox(width: s(16)),
                      Text(
                        'Sign In',
                        style: TextStyle(
                          color: focused ? Colors.black : Colors.white,
                          fontSize: s(24),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar
        _buildSidebar(s),
        // Divider
        Container(
          width: 1,
          height: double.infinity,
          color: Colors.white.withValues(alpha: 0.1),
          margin: EdgeInsets.symmetric(vertical: s(100)),
        ),
        // Content Area
        Expanded(
          child: _buildContent(s),
        ),
      ],
    );
  }

  Widget _buildSidebar(double Function(double) s) {
    return Container(
      width: s(420),
      padding: EdgeInsets.only(top: s(100), left: s(64), right: s(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: s(56),
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: s(64)),
          _SidebarItem(
            label: 'Account',
            icon: Icons.person_outline,
            isSelected: _selectedCategory == _SettingsCategory.account,
            onTap: () => setState(() => _selectedCategory = _SettingsCategory.account),
            s: s,
            focusNode: _sidebarFocusNode,
          ),
          _SidebarItem(
            label: 'Playback',
            icon: Icons.play_circle_outline,
            isSelected: _selectedCategory == _SettingsCategory.playback,
            onTap: () => setState(() => _selectedCategory = _SettingsCategory.playback),
            s: s,
          ),
          _SidebarItem(
            label: 'General',
            icon: Icons.language,
            isSelected: _selectedCategory == _SettingsCategory.general,
            onTap: () => setState(() => _selectedCategory = _SettingsCategory.general),
            s: s,
          ),
          _SidebarItem(
            label: 'About',
            icon: Icons.info_outline,
            isSelected: _selectedCategory == _SettingsCategory.about,
            onTap: () => setState(() => _selectedCategory = _SettingsCategory.about),
            s: s,
          ),
          const Spacer(),
          _SidebarItem(
            label: 'Sign Out',
            icon: Icons.logout,
            isSelected: false,
            onTap: () => _signOut(context),
            s: s,
            isDestructive: true,
          ),
          SizedBox(height: s(64)),
        ],
      ),
    );
  }

  Widget _buildContent(double Function(double) s) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_selectedCategory),
        padding: EdgeInsets.only(top: s(100), left: s(64), right: s(96)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getCategoryTitle(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(40),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: s(48)),
              _buildCategoryView(s),
              SizedBox(height: s(100)),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryTitle() {
    switch (_selectedCategory) {
      case _SettingsCategory.account: return 'Account';
      case _SettingsCategory.playback: return 'Playback';
      case _SettingsCategory.general: return 'General';
      case _SettingsCategory.about: return 'About';
    }
  }

  Widget _buildCategoryView(double Function(double) s) {
    switch (_selectedCategory) {
      case _SettingsCategory.account: return _buildAccountView(s);
      case _SettingsCategory.playback: return _buildPlaybackView(s);
      case _SettingsCategory.general: return _buildGeneralView(s);
      case _SettingsCategory.about: return _buildAboutView(s);
    }
  }

  Widget _buildAccountView(double Function(double) s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile Card
        StreamBuilder<Map<String, dynamic>?>(
          stream: _profileStream,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final dbProfileId = data?['profile_id']?.toString();
            final avatarId = (dbProfileId != null && dbProfileId != '0') ? dbProfileId : (_avatar ?? '0');
            final name = data?['name']?.toString() ?? _name ?? 'User';

            return Container(
              padding: EdgeInsets.all(s(32)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(s(24)),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    width: s(120),
                    height: s(120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(s(24)),
                      image: DecorationImage(
                        image: NetworkImage(AvatarUtils.getAvatarUrl(avatarId)),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(width: s(24)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(color: Colors.white, fontSize: s(32), fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: s(4)),
                        Text(
                          _email ?? '',
                          style: TextStyle(color: Colors.white54, fontSize: s(20)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: s(48)),
        Text('Watch History (Last 14 days)', style: TextStyle(color: Colors.white70, fontSize: s(24), fontWeight: FontWeight.bold)),
        SizedBox(height: s(24)),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Movie Watch Time',
                value: _formatDuration(_movieWatchTimeMs),
                icon: Icons.movie_outlined,
                s: s,
              ),
            ),
            SizedBox(width: s(24)),
            Expanded(
              child: _StatCard(
                label: 'TV Watch Time',
                value: _formatDuration(_tvWatchTimeMs),
                icon: Icons.tv_rounded,
                s: s,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaybackView(double Function(double) s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingHeader('Default Audio Language', s),
        _buildLanguageSelector(_currentAudioLanguage, _updateAudioLanguage, s),
        SizedBox(height: s(48)),
        _buildSettingHeader('Subtitles', s),
        _buildSubtitleToggle(s),
      ],
    );
  }

  Widget _buildGeneralView(double Function(double) s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingHeader('App Language', s),
        _buildLanguageSelector(_currentLanguage, _updateLanguage, s),
        SizedBox(height: s(48)),
        _buildSettingHeader('Watch Region', s),
        _buildRegionSelector(s),
      ],
    );
  }

  Widget _buildAboutView(double Function(double) s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(s(32)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(s(24)),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tv, color: const Color(0xFFDC2626), size: s(48)),
                  SizedBox(width: s(24)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reelriot TV', style: TextStyle(color: Colors.white, fontSize: s(28), fontWeight: FontWeight.bold)),
                      Text('Version 1.2.0 (Build 452)', style: TextStyle(color: Colors.white54, fontSize: s(20))),
                    ],
                  ),
                ],
              ),
              SizedBox(height: s(32)),
              Text(
                'Experience the next generation of home entertainment with Reelriot. Streaming redefined for the big screen.',
                style: TextStyle(color: Colors.white70, fontSize: s(18), height: 1.5),
              ),
            ],
          ),
        ),
        SizedBox(height: s(48)),
        LongPressFocus(
          onTap: () => _checkForUpdate(context),
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(24)),
              decoration: BoxDecoration(
                color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(s(12)),
                border: Border.all(color: focused ? Colors.white : Colors.white24, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _loading 
                    ? SizedBox(width: s(24), height: s(24), child: CircularProgressIndicator(strokeWidth: 2, color: focused ? Colors.black : Colors.white))
                    : Icon(Icons.system_update_alt, color: focused ? Colors.black : Colors.white, size: s(24)),
                  SizedBox(width: s(16)),
                  Text(
                    'Check for Updates',
                    style: TextStyle(
                      color: focused ? Colors.black : Colors.white,
                      fontSize: s(22),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSettingHeader(String title, double Function(double) s) {
    return Padding(
      padding: EdgeInsets.only(bottom: s(16)),
      child: Text(title, style: TextStyle(color: Colors.white70, fontSize: s(24), fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLanguageSelector(String current, Function(String) onSelected, double Function(double) s) {
    return Wrap(
      spacing: s(12),
      runSpacing: s(12),
      children: _languages.map((lang) {
        final isSelected = current == lang['code'];
        return _OptionPill(
          label: lang['name']!,
          isSelected: isSelected,
          onTap: () => onSelected(lang['code']!),
          s: s,
        );
      }).toList(),
    );
  }

  Widget _buildRegionSelector(double Function(double) s) {
    return Wrap(
      spacing: s(12),
      runSpacing: s(12),
      children: _regions.map((reg) {
        final isSelected = _currentRegion == reg['code'];
        return _OptionPill(
          label: reg['name']!,
          isSelected: isSelected,
          onTap: () => _updateRegion(reg['code']!),
          s: s,
        );
      }).toList(),
    );
  }

  Widget _buildSubtitleToggle(double Function(double) s) {
    final enabled = _settings.useExternalSubtitles;
    return LongPressFocus(
      onTap: () => _toggleExternalSubtitles(!enabled),
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          padding: EdgeInsets.all(s(24)),
          decoration: BoxDecoration(
            color: focused ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(s(16)),
            border: Border.all(color: focused ? Colors.white38 : Colors.white12),
          ),
          child: Row(
            children: [
              Icon(
                enabled ? Icons.subtitles : Icons.subtitles_off,
                color: enabled ? const Color(0xFFDC2626) : Colors.white24,
                size: s(32),
              ),
              SizedBox(width: s(24)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('External Subtitles (OpenSubtitles)', style: TextStyle(color: Colors.white, fontSize: s(22), fontWeight: FontWeight.bold)),
                    Text('Automatically download best matches', style: TextStyle(color: Colors.white54, fontSize: s(18))),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) => _toggleExternalSubtitles(v),
                activeThumbColor: const Color(0xFFDC2626),
              ),
            ],
          ),
        );
      }),
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

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final double Function(double) s;
  final bool isDestructive;
  final FocusNode? focusNode;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.s,
    this.isDestructive = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressFocus(
      focusNode: focusNode,
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: s(8)),
          padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(16)),
          decoration: BoxDecoration(
            color: focused ? Colors.white : (isSelected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(s(12)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: focused 
                    ? Colors.black 
                    : (isDestructive ? const Color(0xFFDC2626) : (isSelected ? Colors.white : Colors.white54)),
                size: s(24),
              ),
              SizedBox(width: s(20)),
              Text(
                label,
                style: TextStyle(
                  color: focused 
                      ? Colors.black 
                      : (isDestructive ? const Color(0xFFDC2626) : (isSelected ? Colors.white : Colors.white54)),
                  fontSize: s(22),
                  fontWeight: isSelected || focused ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double Function(double) s;

  const _OptionPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressFocus(
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(12)),
          decoration: BoxDecoration(
            color: isSelected 
                ? (focused ? Colors.white : const Color(0xFFDC2626)) 
                : (focused ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(s(32)),
            border: Border.all(
              color: focused ? Colors.white : (isSelected ? Colors.transparent : Colors.white12),
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected 
                  ? (focused ? Colors.black : Colors.white) 
                  : (focused ? Colors.white : Colors.white70),
              fontSize: s(18),
              fontWeight: isSelected || focused ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final double Function(double) s;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(s(24)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(s(16)),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: s(32)),
          SizedBox(height: s(16)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: s(32),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: s(4)),
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: s(16),
            ),
          ),
        ],
      ),
    );
  }
}
