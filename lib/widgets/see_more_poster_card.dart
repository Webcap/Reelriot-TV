import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

/// The TV equivalent of `rr-web`'s `SeeMoreCard`.
///
/// Placed at the end of media shelves, this card matches the visual
/// footprint and aspect ratio of [PosterCard] while presenting an
/// atmospheric, actionable prompt for D-pad exploration.
///
/// Reaching this card marks the end of a shelf. Pressing right on the D-pad
/// will absorb the event (preventing premature jump to the row below),
/// play an audible click notification, and trigger an end-of-row boundary bump.
class SeeMorePosterCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const SeeMorePosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onFocus,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<SeeMorePosterCard> createState() => _SeeMorePosterCardState();
}

class _SeeMorePosterCardState extends State<SeeMorePosterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bumpController;
  late final Animation<double> _bumpAnimation;

  @override
  void initState() {
    super.initState();
    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _bumpAnimation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(
        parent: _bumpController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _bumpController.dispose();
    super.dispose();
  }

  DateTime? _lastFeedbackTime;

  void _triggerEndOfRowFeedback() {
    final now = DateTime.now();
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastFeedbackTime = now;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    _bumpController.forward(from: 0.0).then((_) {
      if (mounted) {
        _bumpController.reverse();
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }

    if (TvKeys.isRight(event.logicalKey)) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _triggerEndOfRowFeedback();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    final cardWidth = s(153);
    final cardHeight = s(230);

    return Align(
      alignment: Alignment.centerLeft,
      child: LongPressFocus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused) widget.onFocus?.call();
      },
      onTap: widget.onTap,
      onKeyEvent: _handleKeyEvent,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;

          return Semantics(
            label: 'See more: ${widget.title}. Explore all titles.',
            button: true,
            child: AnimatedScale(
              scale: hasFocus ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedBuilder(
                animation: _bumpAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(s(_bumpAnimation.value), 0),
                    child: child,
                  );
                },
                child: SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: RepaintBoundary(
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      decoration: BoxDecoration(
                        color: DashboardTheme.surface,
                        borderRadius: BorderRadius.circular(s(8)),
                        border: Border.all(
                          color: hasFocus
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.08),
                          width: hasFocus ? s(2.5) : s(1),
                        ),
                        boxShadow: hasFocus
                            ? DashboardDecorations.focusGlow(
                                context,
                                strength: 0.8,
                                color: DashboardTheme.signalRed,
                              )
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(s(7)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Layer: Atmospheric Dark Base Gradient
                            Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, -0.4),
                                  radius: 1.1,
                                  colors: [
                                    hasFocus
                                        ? const Color(0x38EC1D24)
                                        : const Color(0x18EC1D24),
                                    const Color(0xEB141418),
                                    const Color(0xFA0A0A0E),
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),

                            // 2. Layer: Ambient Atmospheric Red Glow (intensifies on focus)
                            AnimatedOpacity(
                              opacity: hasFocus ? 0.95 : 0.35,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(0, -0.2),
                                    radius: 0.85,
                                    colors: [
                                      DashboardTheme.signalRed
                                          .withValues(alpha: 0.30),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // 3. Layer: Concentric Inner Border Ring
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: EdgeInsets.all(s(10)),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(s(6)),
                                border: Border.all(
                                  color: hasFocus
                                      ? DashboardTheme.signalRed
                                          .withValues(alpha: 0.50)
                                      : Colors.white.withValues(alpha: 0.08),
                                  width: s(1),
                                ),
                              ),
                            ),

                            // 4. Layer: Center Content, Icon Button & Typography
                            Center(
                              child: Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: s(12)),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Circle action button with animated arrow
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      width: s(54),
                                      height: s(54),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: hasFocus
                                            ? DashboardTheme.signalRed
                                            : Colors.white
                                                .withValues(alpha: 0.08),
                                        border: Border.all(
                                          color: hasFocus
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.18),
                                          width: hasFocus ? s(1.8) : s(1.0),
                                        ),
                                        boxShadow: hasFocus
                                            ? [
                                                BoxShadow(
                                                  color: DashboardTheme
                                                      .signalRed
                                                      .withValues(alpha: 0.65),
                                                  blurRadius: s(22),
                                                  spreadRadius: s(2),
                                                ),
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  blurRadius: s(12),
                                                  offset: Offset(0, s(6)),
                                                ),
                                              ]
                                            : [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: s(10),
                                                  offset: Offset(0, s(4)),
                                                ),
                                              ],
                                      ),
                                      child: Center(
                                        child: AnimatedSlide(
                                          offset: hasFocus
                                              ? const Offset(0.08, 0)
                                              : Offset.zero,
                                          duration: const Duration(
                                              milliseconds: 200),
                                          curve: Curves.easeOutCubic,
                                          child: Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: s(26),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: s(14)),

                                    // Header Badge
                                    Text(
                                      'SEE MORE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: s(12),
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.4,
                                        height: 1.1,
                                      ),
                                    ),
                                    SizedBox(height: s(4)),

                                    // Subtitle
                                    AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        color: hasFocus
                                            ? DashboardTheme.signalRed
                                            : Colors.white38,
                                        fontSize: s(9.5),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.6,
                                      ),
                                      child: Text(
                                        (widget.subtitle ?? 'EXPLORE ALL')
                                            .toUpperCase(),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
}
