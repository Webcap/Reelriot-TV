import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class FakePostgrestFilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> data;
  FakePostgrestFilterBuilder(this.data);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) => this;

  @override
  Future<U> then<U>(FutureOr<U> Function(List<Map<String, dynamic>>) onValue, {Function? onError}) {
    return Future.value(onValue(data));
  }
}

void main() {
  late WatchHistoryService service;
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockUser mockUser;
  late MockSupabaseQueryBuilder mockQueryBuilder;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockUser = MockUser();
    mockQueryBuilder = MockSupabaseQueryBuilder();

    when(() => mockClient.auth).thenAnswer((_) => mockAuth);
    when(() => mockAuth.currentUser).thenAnswer((_) => mockUser);
    when(() => mockUser.id).thenAnswer((_) => 'test-user-id');
    
    when(() => mockClient.from(any())).thenAnswer((_) => mockQueryBuilder);
  });

  group('getHistory', () {
    test('returns empty list when user is null', () async {
      when(() => mockAuth.currentUser).thenAnswer((_) => null);
      service = WatchHistoryService(client: mockClient);
      
      final result = await service.getHistory();
      expect(result, isEmpty);
    });

    test('fetches and normalizes history correctly', () async {
      final mockResponse = [
        {
          'movies': [
            {
              'id': 1,
              'title': 'Test Movie',
              'elapsed': 100,
              'remaining': 900,
              'date_watched': '2023-01-01T00:00:00Z',
            }
          ],
          'tv_shows': []
        }
      ];

      final fakeFilterBuilder = FakePostgrestFilterBuilder(mockResponse);
      when(() => mockQueryBuilder.select(any())).thenAnswer((_) => fakeFilterBuilder);

      service = WatchHistoryService(client: mockClient);
      final result = await service.getHistory();
      
      expect(result, isNotEmpty);
      expect(result.first['media_id'], 1);
      expect(result.first['type'], 'movie');
      expect(result.first['position_ms'], 100000);
    });
  });
}
