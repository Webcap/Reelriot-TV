import 'dart:async';
import 'dart:convert';

import 'package:reelriot_tv/env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
      'User-Agent': 'CaffeineTV/1.0',
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
          _log('Linked', 'received tokens');
          _pollTimer?.cancel();
          final accessToken = data['access_token'] as String?;
          final refreshToken = data['refresh_token'] as String?;
          
          if (refreshToken != null && refreshToken.isNotEmpty && mounted) {
            try {
              if (accessToken != null && accessToken.isNotEmpty) {
                _log('Establishing session with access and refresh tokens');
                // Use access_token and refresh_token to properly establish the session
                await Supabase.instance.client.auth.setSession(
                  '$accessToken $refreshToken', // Some versions support this hack or specific formats
                );
                // Better: if possible, use recoverSession or setSession(Session)
                // But for now, let's try to be robust. 
                // In Supabase Flutter 2.x, setSession expects the full session string or 
                // we can use client.auth.recoverSession(refreshToken)
                await Supabase.instance.client.auth.recoverSession(refreshToken);
              } else {
                _log('Recovering session with refresh token only');
                await Supabase.instance.client.auth.recoverSession(refreshToken);
              }
              _log('Session established successfully');
              if (mounted) _onLinked();
            } catch (e) {
              _log('Session establishment failed', e);
              setState(() => _error = 'Failed to establish session: $e');
            }
          } else {
            _log('Linked but no refresh_token in response');
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
    final effectivePairingPageUrl = widget.pairingPageUrl ?? pairingPageUrl;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Sign in to Caffeine TV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Column(
                  children: [
                    Text(
                      'Connecting to sign-in service…',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                    SizedBox(height: 16),
                    CircularProgressIndicator(color: Colors.white54),
                  ],
                )
              else if (_error != null)
                Column(
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Make sure the Caffeine API is reachable.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _buildButton('Try again', _createCode),
                  ],
                )
              else if (_code != null) ...[
                const Text(
                  'How to sign in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '1. On your phone or computer, open the pairing page.\n'
                    '2. Sign in with your Caffeine account.\n'
                    '3. Enter the code shown below.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                if (effectivePairingPageUrl.isNotEmpty) ...[
                  const Text(
                    'Open this link:',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SelectableText(
                      effectivePairingPageUrl,
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'Your code:',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _code!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildButton('Get new code', _createCode),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: ElevatedButton(
        autofocus: true,
        onPressed: () {
          _log('Button pressed', label);
          onPressed();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 8,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.focused)) return Colors.white.withValues(alpha: 0.1);
              return null;
            },
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
