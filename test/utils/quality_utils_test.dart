import 'package:flutter_test/flutter_test.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';

void main() {
  setUp(() {
    QualityUtils.clearCache();
  });

  tearDown(() {
    QualityUtils.clearCache();
  });

  group('QualityUtils.getQualityBadgeSync', () {
    test('returns HD for TV shows regardless of release date', () {
      final quality = QualityUtils.getQualityBadgeSync(
        releaseDate: '2026-01-01',
        isMovie: false,
      );
      expect(quality, equals('HD'));
    });

    test('returns null for movies with null or empty release date', () {
      expect(
        QualityUtils.getQualityBadgeSync(releaseDate: null, isMovie: true),
        isNull,
      );
      expect(
        QualityUtils.getQualityBadgeSync(releaseDate: '', isMovie: true),
        isNull,
      );
    });

    test('returns SOON for movies with future release dates', () {
      final futureDate = DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10);
      final quality = QualityUtils.getQualityBadgeSync(
        releaseDate: futureDate,
        isMovie: true,
      );
      expect(quality, equals('SOON'));
    });

    test('returns CAM for movies released within 90 days', () {
      final recentDate = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
      final quality = QualityUtils.getQualityBadgeSync(
        releaseDate: recentDate,
        isMovie: true,
      );
      expect(quality, equals('CAM'));
    });

    test('returns HD for movies released more than 90 days ago', () {
      final olderDate = DateTime.now().subtract(const Duration(days: 120)).toIso8601String().substring(0, 10);
      final quality = QualityUtils.getQualityBadgeSync(
        releaseDate: olderDate,
        isMovie: true,
      );
      expect(quality, equals('HD'));
    });

    test('returns null gracefully on malformed dates', () {
      final quality = QualityUtils.getQualityBadgeSync(
        releaseDate: 'not-a-valid-date',
        isMovie: true,
      );
      expect(quality, isNull);
    });
  });

  group('QualityUtils.getQualityBadgeAsync', () {
    test('returns HD immediately for TV shows without network overhead', () async {
      final quality = await QualityUtils.getQualityBadgeAsync(
        mediaId: 99999,
        releaseDate: '2026-01-01',
        isMovie: false,
      );
      expect(quality, equals('HD'));
    });

    test('in-flight deduplication shares the same future for concurrent requests', () async {
      final olderDate = DateTime.now().subtract(const Duration(days: 200)).toIso8601String().substring(0, 10);

      // Fire multiple requests concurrently for the same movie ID
      final future1 = QualityUtils.getQualityBadgeAsync(
        mediaId: 12345,
        releaseDate: olderDate,
        isMovie: true,
      );
      final future2 = QualityUtils.getQualityBadgeAsync(
        mediaId: 12345,
        releaseDate: olderDate,
        isMovie: true,
      );

      final results = await Future.wait([future1, future2]);
      expect(results[0], isNotNull);
      expect(results[0], equals(results[1]));
    });

    test('clearCache removes all entries', () async {
      final olderDate = DateTime.now().subtract(const Duration(days: 200)).toIso8601String().substring(0, 10);
      await QualityUtils.getQualityBadgeAsync(
        mediaId: 54321,
        releaseDate: olderDate,
        isMovie: true,
      );

      QualityUtils.clearCache();

      // Subsequent call can proceed cleanly
      final quality = await QualityUtils.getQualityBadgeAsync(
        mediaId: 54321,
        releaseDate: olderDate,
        isMovie: true,
      );
      expect(quality, isNotNull);
    });
  });
}
