import 'dart:ui';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeProvidersRow extends StatelessWidget {
  final Function(Map<String, dynamic> provider) onProviderTap;

  const HomeProvidersRow({
    super.key,
    required this.onProviderTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    final providers = [
      {'name': 'Netflix', 'id': 8, 'logo': 'assets/svg/Netflix.svg', 'isSvg': true, 'color': const Color(0xFFE50914)},
      {'name': 'Disney+', 'id': 337, 'logo': 'assets/svg/Disney.svg', 'isSvg': true, 'color': const Color(0xFF0063E5)},
      {'name': 'Prime Video', 'id': 9, 'logo': 'assets/svg/Amazon_Prime_Video_logo.svg', 'isSvg': true, 'color': const Color(0xFF00A8E1)},
      {'name': 'Max', 'id': 1899, 'logo': 'assets/svg/Max_logo.svg', 'isSvg': true, 'color': const Color(0xFF0047FF)},
    ];

    return SizedBox(
      height: s(220),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: providers.length,
        separatorBuilder: (_, _) => SizedBox(width: s(40)),
        itemBuilder: (context, index) {
          final p = providers[index];
          return Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
                onProviderTap(p);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () => onProviderTap(p),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(s(24)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: s(360),
                        decoration: BoxDecoration(
                          color: focused 
                              ? Colors.white.withValues(alpha: 0.15) 
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(s(24)),
                          border: Border.all(
                            color: focused ? Colors.white : Colors.white10,
                            width: focused ? s(4) : s(2),
                          ),
                          boxShadow: focused ? [
                            BoxShadow(
                              color: (p['color'] as Color).withValues(alpha: 0.3),
                              blurRadius: s(30),
                              spreadRadius: s(5),
                            )
                          ] : [],
                        ),
                    padding: EdgeInsets.all(s(20)),
                    child: Center(
                      child: p['isSvg'] == true
                          ? SvgPicture.asset(
                              p['logo'] as String,
                              height: s(100),
                              fit: BoxFit.contain,
                              placeholderBuilder: (BuildContext context) => Container(
                                padding: EdgeInsets.all(s(30)),
                                child: const CircularProgressIndicator(),
                              ),
                            )
                          : Image.network(
                              'https://image.tmdb.org/t/p/original${p['logo']}',
                              height: s(100),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Text(
                                p['name'] as String,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: s(36),
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
            );
        },
      ),
    );
  }
}
