import 'dart:async';
import 'dart:convert';

import 'package:caffeine_tv/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  String? _code;
  String? _error;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _createCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _createCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _code = null;
    });
    final base = caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
    try {
      final res = await http.post(
        Uri.parse('$base/tv/pair'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Could not get code';
          _loading = false;
        });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      if (code == null || code.isEmpty) {
        setState(() {
          _error = 'Invalid response';
          _loading = false;
        });
        return;
      }
      setState(() {
        _code = code;
        _loading = false;
        _error = null;
      });
      _startPolling(code);
    } catch (e) {
      setState(() {
        _error = 'Network error';
        _loading = false;
      });
    }
  }

  void _startPolling(String code) {
    _pollTimer?.cancel();
    final base = caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
    void poll() async {
      try {
        final res = await http.get(
          Uri.parse('$base/tv/pair?code=${Uri.encodeComponent(code)}'),
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['linked'] == true) {
          _pollTimer?.cancel();
          final refreshToken = data['refresh_token'] as String?;
          if (refreshToken != null && refreshToken.isNotEmpty && mounted) {
            try {
              await Supabase.instance.client.auth.setSession(refreshToken);
              if (mounted) _onLinked();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  void _onLinked() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Center(
        child: Focus(
          autofocus: true,
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
                const CircularProgressIndicator(color: Colors.white54)
              else if (_error != null)
                Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 18)),
                    const SizedBox(height: 16),
                    _buildButton('Try again', _createCode),
                  ],
                )
              else if (_code != null) ...[
                const Text(
                  'Enter this code on your phone or computer:',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 24),
                if (pairingPageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Go to: $pairingPageUrl',
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Open the Caffeine pairing page on your phone or computer and enter this code.',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),
                _buildButton('Get new code', _createCode),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey.keyLabel == 'Enter' ||
                event.logicalKey.keyId == LogicalKeyboardKey.select.keyId)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: Text(label),
          ),
    );
  }
}
