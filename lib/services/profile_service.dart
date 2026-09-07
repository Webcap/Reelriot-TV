import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/avatar_utils.dart';

/// Centralized service managing the logged-in user's profile state, display name,
/// and avatar image resolution with real-time Supabase sync across TV UI components.
class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;

  ProfileService._internal() {
    // Lazily try to connect if Supabase is already initialized
    try {
      if (Supabase.instance.client.auth.currentSession != null ||
          Supabase.instance.client.auth.currentUser != null) {
        init();
      }
    } catch (_) {
      // Supabase not yet initialized; will be initialized via init() in main
    }
  }

  bool _initialized = false;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;

  Map<String, dynamic>? _profileData;
  String? _avatarUrl;
  String? _displayName;
  String? _username;
  String? _email;
  bool _isSignedIn = false;

  bool get isSignedIn => _isSignedIn;
  String? get avatarUrl => _avatarUrl;
  String? get displayName => _displayName;
  String? get username => _username;
  String? get email => _email;
  Map<String, dynamic>? get profileData => _profileData;

  /// Initializes the service and starts listening to auth and profile changes.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _authSubscription?.cancel();
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        _onAuthChanged(data.session);
      });
      await _onAuthChanged(Supabase.instance.client.auth.currentSession);
    } catch (e) {
      debugPrint('[ProfileService] ⚠️ Initialization error: $e');
    }
  }

  Future<void> _onAuthChanged(Session? session) async {
    _isSignedIn = session != null;
    final user = session?.user ?? Supabase.instance.client.auth.currentUser;

    if (user == null) {
      await _profileSubscription?.cancel();
      _profileSubscription = null;
      _profileData = null;
      _avatarUrl = null;
      _displayName = null;
      _username = null;
      _email = null;
      notifyListeners();
      return;
    }

    _email = user.email;

    // Fast initial resolution from user metadata
    _resolveAvatar(user: user);
    notifyListeners();

    // Fetch latest record from profiles table
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .limit(1);
      if (res.isNotEmpty) {
        _profileData = res.first;
        _resolveAvatar(user: user, profile: _profileData);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ProfileService] ⚠️ Error fetching profile data: $e');
    }

    // Subscribe to real-time updates on the profiles table
    await _profileSubscription?.cancel();
    try {
      _profileSubscription = Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', user.id)
          .limit(1)
          .listen((data) {
            if (data.isNotEmpty) {
              debugPrint('[ProfileService] 🟢 Received real-time profile update');
              _profileData = data.first;
              _resolveAvatar(user: user, profile: _profileData);
              notifyListeners();
            }
          }, onError: (err) {
            debugPrint('[ProfileService] ⚠️ Profile stream error: $err');
          });
    } catch (e) {
      debugPrint('[ProfileService] ⚠️ Could not establish profile stream: $e');
    }
  }

  void _resolveAvatar({User? user, Map<String, dynamic>? profile}) {
    final u = user ?? Supabase.instance.client.auth.currentUser;
    final p = profile ?? _profileData;

    final resolvedUsername = p?['username']?.toString() ??
        u?.userMetadata?['username']?.toString() ??
        u?.email?.split('@')[0];
    _username = (resolvedUsername != null && resolvedUsername.isNotEmpty)
        ? resolvedUsername
        : 'User';
    _displayName = _username;

    // 1. Check custom uploaded image_url in profiles table
    final customImageUrl = p?['image_url']?.toString();
    if (customImageUrl != null && customImageUrl.isNotEmpty) {
      _avatarUrl = AvatarUtils.getAvatarUrl(customImageUrl);
      return;
    }

    // 2. Check profile_id from profiles table
    final dbProfileId = p?['profile_id']?.toString();
    if (dbProfileId != null && dbProfileId.isNotEmpty && dbProfileId != '0') {
      _avatarUrl = AvatarUtils.getAvatarUrl(dbProfileId);
      return;
    }

    // 3. Check avatar, profile_id, or avatar_url from metadata
    final metaAvatar = u?.userMetadata?['avatar']?.toString() ??
        u?.userMetadata?['profile_id']?.toString() ??
        u?.userMetadata?['avatar_url']?.toString();
    if (metaAvatar != null && metaAvatar.isNotEmpty && metaAvatar != '0') {
      _avatarUrl = AvatarUtils.getAvatarUrl(metaAvatar);
      return;
    }

    // 4. If explicitly set to '0', resolve avatar 0
    if (dbProfileId == '0' || metaAvatar == '0') {
      _avatarUrl = AvatarUtils.getAvatarUrl('0');
      return;
    }

    // 5. Default fallback for logged-in user
    _avatarUrl = AvatarUtils.defaultAvatarUrl;
  }

  Future<void> refresh() async {
    await _onAuthChanged(Supabase.instance.client.auth.currentSession);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
