import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reelriot_tv/services/outage_service.dart';

/// Wraps [child] and shows a full-screen outage notification whenever the
/// Caffeine API is detected as unavailable. All user interaction is blocked.
///
/// Place high in the widget tree (e.g., inside MaterialApp.builder) so it
/// covers every route including the home screen and player.
class OutageOverlay extends StatelessWidget {
  final Widget child;
  const OutageOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OutageService.instance.isApiDown,
      builder: (context, isDown, _) {
        return Stack(
          children: [
            child,
            if (isDown)
              const _OutageScreen(),
          ],
        );
      },
    );
  }
}

class _OutageScreen extends StatefulWidget {
  const _OutageScreen();

  @override
  State<_OutageScreen> createState() => _OutageScreenState();
}

class _OutageScreenState extends State<_OutageScreen>
    with TickerProviderStateMixin {
  // Ambient pulsing ring
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Icon glow throb
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  // Dots loading indicator (shown while retrying)
  late final AnimationController _dotsCtrl;

  bool _retrying = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await OutageService.instance.forceCheck();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          color: Colors.black.withValues(alpha: 0.95),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Pulsing ambient ring + icon ──────────────────
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) {
              final scale = 1.0 + 0.06 * _pulseAnim.value;
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, _) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A0000),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC1D24)
                            .withValues(alpha: _glowAnim.value * 0.6),
                        blurRadius: 50,
                        spreadRadius: 8,
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFFEC1D24)
                          .withValues(alpha: _glowAnim.value * 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFFEC1D24),
                    size: 52,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 36),

          // ── Headline ─────────────────────────────────────
          const Text(
            'Service Unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Reelriot is currently experiencing an outage.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w300,
            ),
          ),

          const SizedBox(height: 16),

          // ── Dynamic message from service ─────────────────
          ValueListenableBuilder<String?>(
            valueListenable: OutageService.instance.outageMessage,
            builder: (context, msg, _) {
              if (msg == null) return const SizedBox.shrink();
              return Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC1D24).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEC1D24).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 40),

          // ── Retry button ─────────────────────────────────
          _RetryButton(
            isLoading: _retrying,
            dotsController: _dotsCtrl,
            onTap: _retry,
          ),

          const SizedBox(height: 24),

          // ── Auto-check indicator ─────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Checking automatically every 30 seconds',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Retry Button ────────────────────────────────────────────────────────────

class _RetryButton extends StatefulWidget {
  final bool isLoading;
  final AnimationController dotsController;
  final VoidCallback onTap;

  const _RetryButton({
    required this.isLoading,
    required this.dotsController,
    required this.onTap,
  });

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      autofocus: true,
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isFocused
                ? const Color(0xFFEC1D24)
                : const Color(0xFFEC1D24).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white24,
              width: 2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: const Color(0xFFEC1D24).withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: widget.isLoading
              ? _DotsRow(controller: widget.dotsController)
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Try Again',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DotsRow extends StatelessWidget {
  final AnimationController controller;
  const _DotsRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (controller.value + i / 3) % 1.0;
            final opacity = 0.3 + 0.7 * sin(phase * pi).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * sin(phase * pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
