import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeProvidersRow extends StatelessWidget {
  final Function(Map<String, dynamic> provider) onProviderTap;
  final int index;

  const HomeProvidersRow({
    super.key,
    required this.onProviderTap,
    this.index = 1,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    final providers = [
      {
        'name': 'Netflix',
        'id': 8,
        'logo': 'assets/svg/Netflix.svg',
        'isSvg': true,
        'color': const Color(0xFFE50914),
      },
      {
        'name': 'Disney+',
        'id': 337,
        'logo': 'assets/svg/Disney.svg',
        'isSvg': true,
        'color': const Color(0xFF0063E5),
      },
      {
        'name': 'Prime Video',
        'id': 9,
        'logo': 'assets/svg/Amazon_Prime_Video_logo.svg',
        'isSvg': true,
        'color': const Color(0xFF00A8E1),
      },
      {
        'name': 'Max',
        'id': 1899,
        'logo': 'assets/svg/Max_logo.svg',
        'isSvg': true,
        'color': const Color(0xFF0047FF),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse by Provider',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(40),
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
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
                  if (event is KeyDownEvent &&
                      TvKeys.isSelect(event.logicalKey)) {
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
                      child: AnimatedScale(
                        scale: focused ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: s(360),
                        decoration: BoxDecoration(
                          color: focused
                              ? DashboardTheme.surfaceRaised
                              : DashboardTheme.surface,
                          borderRadius: BorderRadius.circular(s(14)),
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: s(20),
                                    offset: Offset(0, s(10)),
                                  ),
                                  BoxShadow(
                                    color: (p['color'] as Color).withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: s(24),
                                    spreadRadius: s(1),
                                  ),
                                ]
                              : null,
                        ),
                        padding: EdgeInsets.all(s(20)),
                        child: Center(
                          child: p['isSvg'] == true
                              ? SvgPicture.asset(
                                  p['logo'] as String,
                                  height: s(100),
                                  fit: BoxFit.contain,
                                  placeholderBuilder: (BuildContext context) =>
                                      Container(
                                        padding: EdgeInsets.all(s(30)),
                                        child:
                                            const CircularProgressIndicator(),
                                      ),
                                )
                              : Image.network(
                                  'https://image.tmdb.org/t/p/original${p['logo']}',
                                  height: s(100),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Text(
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
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
