import 'dart:async';
import 'dart:math';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/ad_service.dart';
import 'package:caffeine_tv/services/update_service.dart';
import 'package:caffeine_tv/screens/update_screen.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Load posters and config
    try {
      final api = ApiService();
      
      // 1. Load API Config
      try {
        final config = await api.loadConfig().timeout(const Duration(seconds: 10));
        SettingsService().updateFromConfig(config);
        
        // Apply ad configuration
        AdService.instance.updateEnabledStatus(SettingsService().adsEnabled);

        // 1.1 Check for Forced Update
        final apiConfig = core.CaffeineApiConfig.fromMap(config);
        final updateInfo = await UpdateService().checkForUpdate(apiConfig);
        
        if (updateInfo.isUpdateAvailable && updateInfo.isForced) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: updateInfo)),
            );
            return; // Stop bootstrap
          }
        }
      } catch (e) {
        debugPrint('[Splash] Config fetch failed: $e');
      }

      // 2. Fetch posters
      final List<String> paths = [];
      final seen = <String>{};

      Future<void> fetchBatch(Future<core.MovieListResponse> call) async {
        try {
          final page = await call.timeout(const Duration(seconds: 15));
          for (final m in page.results) {
            if (m.posterPath != null && seen.add(m.posterPath!)) {
              paths.add(m.posterPath!);
            }
          }
        } catch (e) {
          debugPrint('[Splash] Batch fetch failed: $e');
        }
      }

      await Future.wait([
        fetchBatch(api.fetchTrendingMovies()),
        fetchBatch(api.fetchPopularMovies()),
        fetchBatch(api.fetchTopRatedMovies()),
      ]);

      // Shuffle so it looks varied every launch
      paths.shuffle(Random());

      if (mounted) {
        setState(() {
          _posterPaths = paths;
          _postersLoaded = true;
        });
        _startScrolling();
      }
    } catch (e) {
      debugPrint('[Splash] Bootstrap error: $e');
      if (mounted) setState(() => _postersLoaded = true);
    }

    // Start content animation after a short delay
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) _contentController.forward();

    // Navigate after splash duration
    await Future.delayed(const Duration(milliseconds: 4000));
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
                      final rawPath = row[idx];
                      final path = rawPath.startsWith('/') ? rawPath : '/$rawPath';
                      final imageUrl = '${tmdbImageBaseUrl}w342$path';
                      
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: posterW,
                          height: posterH,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: posterW,
                            height: posterH,
                            color: Colors.white.withOpacity(0.05),
                          ),
                          errorWidget: (context, url, error) {
                            debugPrint('[Splash] Failed to load image: $imageUrl');
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
                    _LoadingDots(controller: _dotsController),
                  ],
                ),
              ),
            ),
          ),
        ],
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
