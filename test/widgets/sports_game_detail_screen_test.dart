import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:reelriot_tv/screens/sports_game_detail_screen.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;

  setUp(() {
    mockClient = MockHttpClient();
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: SportsGameDetailScreen(
        sport: 'basketball',
        league: 'nba',
        eventId: '401810854',
        gameName: 'Warriors vs Celtics',
        baseUrl: 'http://localhost',
        client: mockClient,
      ),
    );
  }

  testWidgets('renders loading state initially', (tester) async {
    when(() => mockClient.get(any())).thenAnswer((_) async => http.Response('{}', 200));
    
    await tester.pumpWidget(createWidgetUnderTest());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders game details when data is loaded', (tester) async {
    final mockSummary = {
      'header': {
        'status': {'type': {'detail': 'Final'}},
        'competitions': [
          {
            'competitors': [
              {
                'homeAway': 'home',
                'team': {'displayName': 'Boston Celtics', 'logos': [{'href': 'https://logo.com/home'}]},
                'score': '120',
              },
              {
                'homeAway': 'away',
                'team': {'displayName': 'Golden State Warriors', 'logos': [{'href': 'https://logo.com/away'}]},
                'score': '110',
              }
            ]
          }
        ]
      },
      'winProbability': [{'homeWinPercentage': 0.8}],
      'plays': [{'clock': {'displayValue': '12:00'}, 'text': 'Jump ball started'}],
      'players': [
        {
          'team': {'displayName': 'Celtics'},
          'statistics': [
            {
              'athletes': [
                {
                  'athlete': {'displayName': 'Jayson Tatum'},
                  'stats': ['30', '10', '5']
                }
              ]
            }
          ]
        }
      ]
    };

    when(() => mockClient.get(any())).thenAnswer(
      (_) async => http.Response(jsonEncode(mockSummary), 200)
    );

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(); // Start loading
    await tester.pump(); // Finish loading

    expect(find.text('Warriors vs Celtics'), findsOneWidget);
    expect(find.text('Boston Celtics'), findsOneWidget);
    expect(find.text('Golden State Warriors'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    expect(find.text('Win Probability'), findsOneWidget);
    expect(find.text('Recent Plays'), findsOneWidget);
    expect(find.text('Boxscore'), findsOneWidget);
    expect(find.text('Jayson Tatum'), findsOneWidget);
  });

  testWidgets('renders error state on failure', (tester) async {
    when(() => mockClient.get(any())).thenAnswer((_) async => http.Response('Not Found', 404));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(); // Start loading
    await tester.pump(); // Finish loading

    expect(find.textContaining('Failed to load summary: 404'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
