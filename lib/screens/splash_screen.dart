import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/ad_service.dart';
import 'package:caffeine_tv/services/update_service.dart';
import 'package:caffeine_tv/screens/update_screen.dart';
import 'package:caffeine_tv/env.dart';
import 'package:flutter/material.dart';


class SplashScreen extends StatefulWidget {
  final Widget destination;
  const SplashScreen({super.key, required this.destination});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // --- Poster data ---
  List<String> _posterPaths = [];
  bool _postersLoaded = false;
  bool _hasError = false;
  String? _errorMessage;

  // --- Scrolling controllers (one per row) ---
  static const int _rowCount = 4;
  final List<ScrollController> _scrollControllers =
      List.generate(_rowCount, (_) => ScrollController());
  final List<Timer> _scrollTimers = [];

  // --- Content animation ---
  late AnimationController _contentController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // --- Logo pulse ---
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // --- Dots loading ---
  late AnimationController _dotsController;

  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();

    // Content fade + slide
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _contentController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic));

    // Logo pulse glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Dots
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _loadLocalPosters();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_isRetrying) return;

    setState(() {
      _isRetrying = true;
    });

    // 1. Run all critical async tasks in parallel for speed
    try {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });

      final api = ApiService();

      // Parallelize initialization tasks with strict timeouts for low-spec TV hardware
      final results = await Future.wait([
        core.FeatureFlagManager().initialize(
          apiUrl: caffeineApiUrl,
          environment: environment,
          platform: 'tv',
        ).timeout(const Duration(seconds: 3)).catchError((e) {
          debugPrint('[Splash] FeatureFlagManager failed or timed out: $e');
          return null; 
        }),
        api.loadConfig().timeout(const Duration(seconds: 3)).catchError((e) {
          debugPrint('[Splash] Config load failed or timed out: $e');
          return <String, dynamic>{}; // Return empty map instead of null
        }),
        UpdateService().checkForUpdate(
          caffeineApiUrl,
          env: environment,
          apiKey: caffeineApiKey,
        ).timeout(const Duration(seconds: 3)).catchError((e) {
          debugPrint('[Splash] Update check failed or timed out: $e');
          return UpdateInfo(
            isUpdateAvailable: false,
            latestVersion: '',
            currentVersion: '',
            isForced: false,
          ); 
        }),
      ]);

      // Handle config result
      final config = results[1] as Map<String, dynamic>?;
      if (config != null) {
        SettingsService().updateFromConfig(config);
      }

      // Handle update result
      final updateInfo = results[2] as UpdateInfo?;
      if (updateInfo != null && updateInfo.isUpdateAvailable && updateInfo.isForced) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: updateInfo)),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[Splash] Bootstrap tasks failed (non-critical items): $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }

    await _finishBootstrapTransition();
  }


  void _startScrolling() {
    for (int i = 0; i < _rowCount; i++) {
      // Alternate rows scroll right/left
      final reverse = i.isOdd;
      // Stagger start
      Timer(Duration(milliseconds: i * 150), () {
        if (!mounted) return;
        _animateRow(i, reverse);
      });
    }
  }

  void _animateRow(int index, bool reverse) {
    final ctrl = _scrollControllers[index];

    // Scroll at ~30px/s continuously using a periodic ticker
    const fps = 60;
    const pixelsPerFrame = 0.6; // slightly faster drift
    final timer = Timer.periodic(
      const Duration(milliseconds: 1000 ~/ fps),
      (_) {
        if (!mounted || !ctrl.hasClients) return;
        final max = ctrl.position.maxScrollExtent;
        if (max <= 0) return;
        double next;
        if (reverse) {
          next = ctrl.offset - pixelsPerFrame;
          if (next < 0) next = max;
        } else {
          next = ctrl.offset + pixelsPerFrame;
          if (next > max) next = 0;
        }
        ctrl.jumpTo(next);
      },
    );
    _scrollTimers.add(timer);
  }

  @override
  void dispose() {
    for (final t in _scrollTimers) {
      t.cancel();
    }
    for (final c in _scrollControllers) {
      c.dispose();
    }
    _contentController.dispose();
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  // Distribute posters across rows
  List<List<String>> get _rows {
    if (_posterPaths.isEmpty) return List.generate(_rowCount, (_) => []);
    final rows = List.generate(_rowCount, (_) => <String>[]);
    for (int i = 0; i < _posterPaths.length; i++) {
      rows[i % _rowCount].add(_posterPaths[i]);
    }
    // Duplicate each row so we can loop seamlessly and fill screen width
    return rows.map((r) {
      if (r.isEmpty) return <String>[];
      final List<String> repeated = [];
      while (repeated.length < 25) {
        repeated.addAll(r);
      }
      return repeated;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Scrolling poster grid ──────────────────────────
          if (_postersLoaded && _posterPaths.isNotEmpty)
            Column(
              children: List.generate(_rowCount, (i) {
                final row = rows[i];
                if (row.isEmpty) return const Expanded(child: SizedBox.shrink());
                const posterW = 130.0;
                const posterH = 195.0;
                const gap = 10.0;
                return Expanded(
                  child: ListView.separated(
                    controller: _scrollControllers[i],
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      top: i == 0 ? 0 : 5,
                      bottom: i == _rowCount - 1 ? 0 : 5,
                    ),
                    itemCount: row.length,
                    separatorBuilder: (_, __) => const SizedBox(width: gap),
                    itemBuilder: (_, idx) {
                      final path = row[idx];
                      
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          path,
                          width: posterW,
                          height: posterH,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('[Splash] Failed to load local asset: $path');
                            return Container(
                              width: posterW,
                              height: posterH,
                              color: const Color(0xFF1A1A1A),
                              child: const Icon(Icons.movie_outlined, color: Colors.white10, size: 24),
                            );
                          },
                        ),
                      );
                    },
                  ),

                );
              }),
            ),

          // ── Dark + red gradient overlay ────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Color(0x99000000), // 60% opacity
                  Color(0xDD000000), // 86% opacity
                ],
              ),
            ),
          ),
          // Edge vignette
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.85),
                ],
                stops: const [0.0, 0.2, 0.75, 1.0],
              ),
            ),
          ),

          // ── Centre content ─────────────────────────────────
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glowing logo badge
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 36, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC1D24),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEC1D24)
                                    .withOpacity(_pulseAnim.value * 0.6),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: const Text(
                            'CAFFEINE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Tagline
                    const Text(
                      'Stream Everything.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 48),
                    // Animated loading dots
                    if (!_hasError) _LoadingDots(controller: _dotsController),
                  ],
                ),
              ),
            ),
          ),

          // ── Error Overlay ──────────────────────────────────
          if (_hasError)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(
                    child: Container(
                      width: 450,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC1D24).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              color: Color(0xFFEC1D24),
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Connection reaching caffeine API failed',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage ?? 'Please check your internet connection or try again later.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 16,
                            ),
                          ),
                           const SizedBox(height: 40),
                          SizedBox(
                            width: 240,
                            child: _MenuButton(
                              label: 'Try Again',
                              icon: Icons.refresh_rounded,
                              isPrimary: true,
                              isLoading: _isRetrying,
                              onTap: () => _bootstrap(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _loadLocalPosters() {
    // Load posters and start scrolling immediately for immediate visual feedback
    const String posterDir = 'assets/images/posters/';
    final List<String> localPosters = [
      '1_Peaky Blinders The Immortal Man.jpg', '2_Project Hail Mary.jpg', '3_How to Make a Killing.jpg',
      '4_Agent Zeta.jpg', '5_Send Help.jpg', '6_They Will Kill You.jpg', '7_War Machine.jpg',
      '8_Greenland 2 Migration.jpg', '9_GOAT.jpg', '10_Scream 7.jpg', '11_Avatar Fire and Ash.jpg',
      '12_Zootopia 2.jpg', '13_Marty Supreme.jpg', '14_Hoppers.jpg', '15_Dhurandhar The Revenge.jpg',
      '16_The Drama.jpg', '17_Spider-Man Brand New Day.jpg', '18_Ready or Not Here I Come.jpg',
      '19_Scary Movie.jpg', '20_One Battle After Another.jpg', 'movie_1_Project Hail Mary.jpg',
      'movie_2_Send Help.jpg', 'movie_3_GOAT.jpg', 'movie_4_Mike  Nick  Nick  Alice.jpg',
      'movie_5_Pretty Lethal.jpg', 'movie_6_Hoppers.jpg', 'movie_7_Peaky Blinders The Immortal Man.jpg',
      'movie_8_The Super Mario Galaxy Movie.jpg', 'movie_9_How to Make a Killing.jpg', 'movie_10_Scream 7.jpg',
      'tv_1_JUJUTSU KAISEN.jpg', 'tv_2_Daredevil Born Again.jpg', 'tv_3_Frieren Beyond Journeys End.jpg',
      'tv_4_One Piece.jpg', 'tv_5_ONE PIECE.jpg', 'tv_6_Something Very Bad is Going to Happen.jpg',
      'tv_7_Scrubs.jpg', 'tv_8_Invincible.jpg', 'tv_9_Detective Hole.jpg', 'tv_10_The Pitt.jpg'
    ];

    final paths = localPosters.map((p) => '$posterDir$p').toList();
    paths.shuffle(Random());

    if (mounted) {
      setState(() {
        _posterPaths = paths;
        _postersLoaded = true;
      });
      _startScrolling();
      // Start content animation immediately
      _contentController.forward();
    }
  }

  Future<void> _finishBootstrapTransition() async {
    // Wait for a minimal time to ensure the animation is visible
    await Future.delayed(const Duration(milliseconds: 600));
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.destination,
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
              child: child,
            );
          },
        ),
      );
    }
  }
}

class _MenuButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.isLoading) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_MenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _rotationController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isFocused
                ? (widget.isPrimary ? const Color(0xFFEC1D24) : Colors.white10)
                : (widget.isPrimary
                    ? const Color(0xFFEC1D24).withOpacity(0.8)
                    : Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white12,
              width: 2,
            ),
            boxShadow: _isFocused && widget.isPrimary
                ? [
                    BoxShadow(
                      color: const Color(0xFFEC1D24).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: _rotationController,
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.isLoading ? 'Retrying...' : widget.label,
                style: const TextStyle(
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

/// Three pulsing dots, each offset by 120°
class _LoadingDots extends StatelessWidget {
  final AnimationController controller;
  const _LoadingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger phase per dot
            final phase = (controller.value + i / 3) % 1.0;
            final scale = 0.6 + 0.4 * sin(phase * pi);
            final opacity = 0.3 + 0.7 * sin(phase * pi).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEC1D24),
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
