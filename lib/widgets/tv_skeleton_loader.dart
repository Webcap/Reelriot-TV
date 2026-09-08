import 'package:flutter/material.dart';

/// Reusable zero-CLS shimmer effect for 10-foot TV UI.
class TvShimmer extends StatefulWidget {
  const TvShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF1E1E1E),
    this.highlightColor = const Color(0xFF2E2E2E),
    this.duration = const Duration(milliseconds: 1500),
  });

  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  @override
  State<TvShimmer> createState() => _TvShimmerState();
}

class _TvShimmerState extends State<TvShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double value = _controller.value;
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              stops: [
                (value - 0.3).clamp(0.0, 1.0),
                value.clamp(0.0, 1.0),
                (value + 0.3).clamp(0.0, 1.0),
              ],
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Skeleton placeholder for a single poster card in a 6-column grid.
class TvGridPosterSkeleton extends StatelessWidget {
  const TvGridPosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 16,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          width: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

/// Zero-CLS skeleton grid for Favorites and grid-based screens.
class TvGridSkeleton extends StatelessWidget {
  const TvGridSkeleton({
    super.key,
    this.title = 'My Favorites',
    this.itemCount = 12,
  });

  final String title;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return TvShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              height: 22,
              width: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 0.7,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) => const TvGridPosterSkeleton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zero-CLS skeleton for horizontal category sections (Movies & TV Shows screens).
class TvRowSkeleton extends StatelessWidget {
  const TvRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            width: 160,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 8,
              itemBuilder: (context, index) {
                return Container(
                  width: 153, // 230 * 0.7 child aspect ratio approx
                  margin: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Zero-CLS skeleton screen for Movies and TV Shows browsing screens.
class TvBrowseScreenSkeleton extends StatelessWidget {
  const TvBrowseScreenSkeleton({super.key, this.sectionCount = 3});

  final int sectionCount;

  @override
  Widget build(BuildContext context) {
    return TvShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sectionCount,
        itemBuilder: (context, index) => const TvRowSkeleton(),
      ),
    );
  }
}

/// Zero-CLS skeleton for search result tiles mirroring _ResultTile.
class TvSearchResultTileSkeleton extends StatelessWidget {
  const TvSearchResultTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 70,
            height: 105,
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 20,
                  width: 260,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      height: 14,
                      width: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      height: 14,
                      width: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 14,
                  width: 320,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Zero-CLS search results skeleton screen.
class TvSearchResultsSkeleton extends StatelessWidget {
  const TvSearchResultsSkeleton({super.key, this.tileCount = 5});

  final int tileCount;

  @override
  Widget build(BuildContext context) {
    return TvShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Container(
            height: 18,
            width: 120,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          ...List.generate(
            tileCount,
            (index) => const TvSearchResultTileSkeleton(),
          ),
        ],
      ),
    );
  }
}

/// Zero-CLS skeleton screen for SportsScreen mirroring exact header, filters, and game cards.
class TvSportsScreenSkeleton extends StatelessWidget {
  const TvSportsScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double s(double v) => (v * width) / 1920;

    return TvShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(s(48)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title & Date + Refresh Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: s(280),
                      height: s(56),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(s(8)),
                      ),
                    ),
                    SizedBox(height: s(8)),
                    Container(
                      width: s(180),
                      height: s(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(s(4)),
                      ),
                    ),
                  ],
                ),
                Container(
                  width: s(130),
                  height: s(52),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(s(12)),
                  ),
                ),
              ],
            ),
            SizedBox(height: s(40)),

            // Sport Filter Chips Row
            SizedBox(
              height: s(60),
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildChipSkeleton(s, s(90)),
                  _buildChipSkeleton(s, s(120)),
                  _buildChipSkeleton(s, s(105)),
                  _buildChipSkeleton(s, s(140)),
                  _buildChipSkeleton(s, s(110)),
                  _buildChipSkeleton(s, s(130)),
                  _buildChipSkeleton(s, s(95)),
                ],
              ),
            ),
            SizedBox(height: s(40)),

            // Section 1: LIVE NOW
            _buildSectionSkeleton(s, titleWidth: s(180), eventCountWidth: s(80)),
            SizedBox(height: s(48)),

            // Section 2: UPCOMING
            _buildSectionSkeleton(s, titleWidth: s(160), eventCountWidth: s(90)),
          ],
        ),
      ),
    );
  }

  Widget _buildChipSkeleton(double Function(double) s, double width) {
    return Container(
      width: width,
      height: s(46),
      margin: EdgeInsets.only(right: s(16)),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(s(30)),
      ),
    );
  }

  Widget _buildSectionSkeleton(
    double Function(double) s, {
    required double titleWidth,
    required double eventCountWidth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          children: [
            Container(
              width: s(4),
              height: s(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(s(2)),
              ),
            ),
            SizedBox(width: s(12)),
            Container(
              width: titleWidth,
              height: s(34),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(s(6)),
              ),
            ),
            const Spacer(),
            Container(
              width: eventCountWidth,
              height: s(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(s(4)),
              ),
            ),
          ],
        ),
        SizedBox(height: s(24)),

        // Horizontal Game Cards Rail
        SizedBox(
          height: s(200),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            separatorBuilder: (_, _) => SizedBox(width: s(16)),
            itemBuilder: (_, _) => _buildGameCardSkeleton(s),
          ),
        ),
      ],
    );
  }

  Widget _buildGameCardSkeleton(double Function(double) s) {
    return Container(
      width: s(360),
      height: s(200),
      padding: EdgeInsets.all(s(20)),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F14),
        borderRadius: BorderRadius.circular(s(16)),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: s(80),
                height: s(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
              ),
              Container(
                width: s(60),
                height: s(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(6)),
                ),
              ),
            ],
          ),
          SizedBox(height: s(16)),

          // Team 1
          Row(
            children: [
              Container(
                width: s(36),
                height: s(36),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(6)),
                ),
              ),
              SizedBox(width: s(12)),
              Container(
                width: s(140),
                height: s(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
              ),
              const Spacer(),
              Container(
                width: s(28),
                height: s(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
              ),
            ],
          ),
          SizedBox(height: s(10)),

          // Team 2
          Row(
            children: [
              Container(
                width: s(36),
                height: s(36),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(6)),
                ),
              ),
              SizedBox(width: s(12)),
              Container(
                width: s(120),
                height: s(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
              ),
              const Spacer(),
              Container(
                width: s(28),
                height: s(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

