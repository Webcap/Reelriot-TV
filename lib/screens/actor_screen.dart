import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ActorScreen extends StatefulWidget {
  final int personId;
  const ActorScreen({super.key, required this.personId});

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  final ApiService _api = ApiService();
  PersonDetail? _person;
  List<CombinedCreditItem>? _credits;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final person = await _api.fetchPersonDetail(widget.personId);
      final credits = await _api.fetchPersonCombinedCredits(widget.personId);
      
      if (mounted) {
        setState(() {
          _person = person;
          // Sort credits by popularity or release date if available? 
          // For now just take what TMDB gives.
          _credits = credits.cast;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => _scale(context, v);
    
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFEC1D24))),
      );
    }

    if (_person == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(
          child: Text(
            'Failed to load actor info',
            style: TextStyle(color: Colors.white, fontSize: s(32)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(s(48)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile image
                  if (_person!.profilePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(s(24)),
                      child: CachedNetworkImage(
                        imageUrl: '$tmdbImageBaseUrl/h632${_person!.profilePath}',
                        width: s(400),
                        height: s(600),
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: s(400),
                      height: s(600),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(s(24)),
                      ),
                      child: Icon(Icons.person, size: s(100), color: Colors.white24),
                    ),
                  SizedBox(width: s(64)),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _person!.name.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(72),
                            fontWeight: FontWeight.w900,
                            letterSpacing: s(2),
                          ),
                        ),
                        if (_person!.knownForDepartment != null) ...[
                          SizedBox(height: s(12)),
                          Text(
                            _person!.knownForDepartment!,
                            style: TextStyle(
                              color: const Color(0xFFEC1D24),
                              fontSize: s(28),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        SizedBox(height: s(32)),
                        if (_person!.biography != null && _person!.biography!.isNotEmpty)
                          Text(
                            _person!.biography!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: s(22),
                              height: 1.5,
                            ),
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                          ),
                        SizedBox(height: s(32)),
                        if (_person!.birthday != null)
                          _buildInfoRow(s, 'Birthday', _person!.birthday!),
                        if (_person!.placeOfBirth != null)
                          _buildInfoRow(s, 'Place of Birth', _person!.placeOfBirth!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_credits != null && _credits!.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: s(48)),
                child: Text(
                  'KNOWN FOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s(32),
                    fontWeight: FontWeight.w800,
                    letterSpacing: s(1.5),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.all(s(48)),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: s(24),
                  mainAxisSpacing: s(48),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _credits![index];
                    return PosterCard(
                      posterPath: item.posterPath,
                      title: (item.mediaType == 'movie' ? item.title : item.name) ?? '',
                      onTap: () {
                        if (item.mediaType == 'movie') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MovieDetailScreen(movieId: item.id),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TvDetailScreen(tvId: item.id),
                            ),
                          );
                        }
                      },
                      quality: QualityUtils.getQualityBadgeSync(
                        releaseDate: item.mediaType == 'movie' ? item.releaseDate : item.firstAirDate,
                        isMovie: item.mediaType == 'movie',
                      ),
                      mediaId: item.id,
                      isMovie: item.mediaType == 'movie',
                    );
                  },
                  childCount: _credits!.length > 24 ? 24 : _credits!.length, // Limit for better performance on first load
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(double Function(double) s, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: s(12)),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.white54, fontSize: s(20)),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.white, fontSize: s(20), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
