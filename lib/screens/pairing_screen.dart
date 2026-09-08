import 'dart:async';
import 'dart:convert';

import 'package:reelriot_tv/env.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

void _log(String message, [Object? detail]) {
  if (kDebugMode) {
    debugPrint('[Pairing] $message${detail != null ? ': $detail' : ''}');
  }
}

class PairingScreen extends StatefulWidget {
  final http.Client? client;
  final String? baseUrl;
  final String? pairingPageUrl;

  const PairingScreen({
    super.key,
    this.client,
    this.baseUrl,
    this.pairingPageUrl,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  String? _code;
  String? _error;
  bool _loading = true;
  Timer? _pollTimer;

  Map<String, String> get _authHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'ReelriotTV/1.0',
    };
    if (caffeineApiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $caffeineApiKey';
    }
    return headers;
  }

  @override
  void initState() {
    super.initState();
    // Proactive check: if we somehow landed here with a session, go home immediately.
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      _log('Proactive check: Session found, navigating home');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onLinked();
      });
      return;
    }
    _createCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _createCode() async {
    final base = (widget.baseUrl ?? caffeineApiUrl).replaceFirst(RegExp(r'/$'), '');
    final url = '$base/tv/pair';
    
    _log('Requesting pairing code from', url);
    setState(() {
      _loading = true;
      _error = null;
      _code = null;
    });
    
    final client = widget.client ?? http.Client();
    
    try {
      _log('Sending POST request to /tv/pair');
      final res = await client.post(
        Uri.parse(url),
        headers: _authHeaders,
        body: '{}',
      ).timeout(const Duration(seconds: 10));
      
      _log('POST /tv/pair response', 'status=${res.statusCode} body=${res.body.length} chars');
      
      if (!mounted) {
        if (widget.client == null) client.close();
        return;
      }

      if (res.statusCode != 200) {
        final body = res.body.length > 80 ? '${res.body.substring(0, 80)}…' : res.body;
        _log('Code request failed', '${res.statusCode} $body');
        setState(() {
          _error = 'Could not get code (${res.statusCode})${body.isNotEmpty ? ': $body' : ''}';
          _loading = false;
        });
        if (widget.client == null) client.close();
        return;
      }
      
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      
      if (code == null || code.isEmpty) {
        _log('Invalid response', 'missing or empty code');
        setState(() {
          _error = 'Invalid response';
          _loading = false;
        });
        if (widget.client == null) client.close();
        return;
      }
      
      _log('Code received and updated in state', code);
      setState(() {
        _code = code;
        _loading = false;
        _error = null;
      });
      if (widget.client == null) client.close();
      _log('Starting poll with new code');
      _startPolling(code);
    } catch (e, stack) {
      _log('Network/request error', e);
      if (kDebugMode) debugPrint(stack.toString());
      if (mounted) {
        setState(() {
          _error = 'Network error: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}';
          _loading = false;
        });
      }
      if (widget.client == null) client.close();
    }
  }

  void _startPolling(String code) {
    _pollTimer?.cancel();
    _log('Started polling for code', code);
    
    void poll() async {
      try {
        final client = widget.client ?? http.Client();
        final base = (widget.baseUrl ?? caffeineApiUrl).replaceFirst(RegExp(r'/$'), '');
        final res = await client.get(
          Uri.parse('$base/tv/pair?code=${Uri.encodeComponent(code)}'),
          headers: _authHeaders,
        ).timeout(const Duration(seconds: 8));
        
        if (!mounted) {
          if (widget.client == null) client.close();
          return;
        }

        if (res.statusCode != 200) {
          _log('Poll non-200', res.statusCode);
          if (widget.client == null) client.close();
          return;
        }
        
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['linked'] == true) {
          _log('Linked', 'received token_hash');
          _pollTimer?.cancel();
          final tokenHash = data['token_hash'] as String?;

          if (tokenHash != null && tokenHash.isNotEmpty && mounted) {
            try {
              _log('Establishing an independent TV session via verifyOTP');

              // The backend mints this TV a one-time magic-link token of its
              // own (see /tv/pair/confirm) rather than forwarding the
              // confirming device's session — redeeming it here gives this
              // TV its own session id and refresh token, so signing out on
              // one device no longer signs out the other.
              await Supabase.instance.client.auth.verifyOTP(
                type: OtpType.magiclink,
                tokenHash: tokenHash,
              );

              _log('Session established successfully');
              if (mounted) _onLinked();
            } catch (e, st) {
              _log('Session establishment failed', e);
              debugPrint('Stack trace: $st');
              setState(() => _error = 'Session pairing failed: $e');
            }
          } else {
            _log('Linked but no token_hash in response');
            setState(() => _error = 'Invalid response from pairing service');
          }
        }
        if (widget.client == null) client.close();
      } catch (e) {
        _log('Poll error', e);
      }
    }
    
    poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  void _onLinked() {
    _log('Navigating to home');
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final effectivePairingPageUrl = widget.pairingPageUrl ??
        (pairingPageUrl.isEmpty ? 'reelriot.app/activate' : pairingPageUrl);
    double s(double v) => ResponsiveUtils.scale(context, v);

    Widget content;
    if (_loading) {
      content = _buildLoadingState(s);
    } else if (_error != null) {
      content = _buildErrorState(s);
    } else if (_code != null) {
      content = _buildCodeState(s, effectivePairingPageUrl);
    } else {
      content = const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Faint ambient glow, top-left — echoes the signal-red accent used
          // across the rest of the app without theming this screen on its own.
          Positioned(
            top: -s(200),
            left: -s(200),
            child: Container(
              width: s(700),
              height: s(700),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    DashboardTheme.signalRed.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: s(56), vertical: s(48)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: s(1400)),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: content,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandMark(double Function(double) s) {
    return Container(
      width: s(64),
      height: s(64),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s(14)),
        boxShadow: [
          BoxShadow(
            color: DashboardTheme.signalRed.withValues(alpha: 0.35),
            blurRadius: s(18),
            spreadRadius: s(1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(14)),
        child: Image.asset(
          'assets/images/ReelriotTVLogo.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildLoadingState(double Function(double) s) {
    return Column(
      key: const ValueKey('pairing_loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _brandMark(s),
        SizedBox(height: s(32)),
        Text(
          'Connecting to sign-in service…',
          style: DashboardTheme.heroMeta(context).copyWith(fontSize: s(22)),
        ),
        SizedBox(height: s(28)),
        SizedBox(
          width: s(28),
          height: s(28),
          child: const CircularProgressIndicator(
            color: DashboardTheme.signalRed,
            strokeWidth: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(double Function(double) s) {
    return Column(
      key: const ValueKey('pairing_error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: s(72),
          height: s(72),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DashboardTheme.signalRed.withValues(alpha: 0.12),
            border: Border.all(
              color: DashboardTheme.signalRed.withValues(alpha: 0.4),
              width: s(1.5),
            ),
          ),
          child: Icon(
            Icons.wifi_off_rounded,
            color: DashboardTheme.signalRed,
            size: s(34),
          ),
        ),
        SizedBox(height: s(28)),
        Text(
          _error!,
          style: TextStyle(
            color: Colors.white,
            fontSize: s(22),
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: s(10)),
        Text(
          'Make sure the Reelriot API is reachable.',
          style: TextStyle(color: Colors.white54, fontSize: s(16)),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: s(32)),
        _ActionButton(
          label: 'Try again',
          isPrimary: true,
          autofocus: true,
          onTap: () {
            _log('Button pressed', 'Try again');
            _createCode();
          },
        ),
      ],
    );
  }

  Widget _buildCodeState(double Function(double) s, String pairingPageUrl) {
    final steps = [
      'On your phone or computer, go to $pairingPageUrl',
      'Sign in with your Reelriot account.',
      'Enter the code shown here.',
    ];

    return Row(
      key: const ValueKey('pairing_code'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left column — brand + step-by-step instructions.
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _brandMark(s),
              SizedBox(height: s(28)),
              Text(
                'Sign in to Reelriot TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(42),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
              SizedBox(height: s(28)),
              Text(
                'How to sign in',
                style: DashboardTheme.sectionTitle(context),
              ),
              SizedBox(height: s(20)),
              for (var i = 0; i < steps.length; i++) ...[
                _buildStep(s, i + 1, steps[i]),
                if (i != steps.length - 1) SizedBox(height: s(18)),
              ],
            ],
          ),
        ),
        SizedBox(width: s(64)),
        // Right column — the code panel.
        Expanded(
          flex: 4,
          child: Container(
            padding: EdgeInsets.all(s(36)),
            decoration: BoxDecoration(
              color: DashboardTheme.surface,
              borderRadius: BorderRadius.circular(s(20)),
              border: Border.all(color: DashboardTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'YOUR CODE',
                  style: DashboardTheme.sectionTitle(context)
                      .copyWith(color: Colors.white54),
                ),
                SizedBox(height: s(16)),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: s(24)),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: DashboardTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(s(14)),
                    border: Border.all(
                      color: DashboardTheme.signalRed.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _code!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: s(48),
                      letterSpacing: s(10),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (pairingPageUrl.isNotEmpty) ...[
                  SizedBox(height: s(28)),
                  Text(
                    'OPEN THIS LINK',
                    style: DashboardTheme.sectionTitle(context)
                        .copyWith(color: Colors.white54),
                  ),
                  SizedBox(height: s(10)),
                  SelectableText(
                    pairingPageUrl,
                    style: TextStyle(
                      color: DashboardTheme.signalRed,
                      fontSize: s(20),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                SizedBox(height: s(32)),
                _ActionButton(
                  label: 'Get new code',
                  isPrimary: false,
                  autofocus: true,
                  onTap: () {
                    _log('Button pressed', 'Get new code');
                    _createCode();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep(double Function(double) s, int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: s(30),
          height: s(30),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DashboardTheme.surfaceRaised,
            border: Border.all(color: DashboardTheme.dividerBright),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: Colors.white,
              fontSize: s(14),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(width: s(16)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: s(4)),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white70,
                fontSize: s(18),
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Focusable pill button matching the home dashboard's action-button
/// language (accent gradient primary, soft-lift focus glow).
class _ActionButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final bool autofocus;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return LongPressFocus(
      autofocus: autofocus,
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: s(36), vertical: s(18)),
          decoration: BoxDecoration(
            gradient: isPrimary ? DashboardTheme.accentGradient : null,
            color: isPrimary
                ? null
                : (focused
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(s(30)),
            border: Border.all(
              color: focused
                  ? Colors.white
                  : (isPrimary
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.2)),
              width: focused ? s(2.5) : s(1),
            ),
            boxShadow: focused
                ? DashboardDecorations.focusGlow(
                    context,
                    strength: isPrimary ? 0.9 : 0.6,
                    color: isPrimary ? DashboardTheme.signalRed : null,
                  )
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: s(18),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        );
      }),
    );
  }
}
