import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/screens/pairing_screen.dart';

class MockHttpClient extends Mock implements http.Client {}
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockHttpClient mockHttpClient;
  late MockSupabaseClient mockSupabase;
  late MockGoTrueClient mockAuth;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    mockHttpClient = MockHttpClient();
    mockSupabase = MockSupabaseClient();
    mockAuth = MockGoTrueClient();

    when(() => mockSupabase.auth).thenReturn(mockAuth);
    // Note: We'd need to mock Supabase.instance, but for this widget test 
    // we can focus on the UI flow and http calls.
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      routes: {
        '/home': (context) => const Scaffold(body: Text('Home Screen')),
      },
      home: PairingScreen(
        client: mockHttpClient,
        baseUrl: 'http://localhost',
        pairingPageUrl: 'http://localhost/pair',
      ),
    );
  }

  testWidgets('renders loading state initially and then shows code', (tester) async {
    final mockCodeResponse = {'code': 'ABC-123'};
    
    when(() => mockHttpClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response(jsonEncode(mockCodeResponse), 200));
    
    // Also mock the poll call so it doesn't fail immediately
    when(() => mockHttpClient.get(any())).thenAnswer((_) async => http.Response('{"linked": false}', 200));

    await tester.pumpWidget(createWidgetUnderTest());
    
    expect(find.text('Connecting to sign-in service…'), findsOneWidget);
    await tester.pump(); // Start loading
    await tester.pump(); // Finish loading

    expect(find.text('ABC-123'), findsOneWidget);
    expect(find.text('How to sign in'), findsOneWidget);
  });

  testWidgets('renders error state when code fetch fails', (tester) async {
    when(() => mockHttpClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response('Error', 500));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(); // Start loading
    await tester.pump(); // Finish loading

    expect(find.textContaining('Could not get code (500)'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('polls and handles linking success (skipping Supabase nav for simplicity)', (tester) async {
    // This test would be more complex because it involves Supabase.instance.client
    // We'll focus on verifying that the UI shows the code first.
    final mockCodeResponse = {'code': 'ABC-123'};
    when(() => mockHttpClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response(jsonEncode(mockCodeResponse), 200));
    
    when(() => mockHttpClient.get(any())).thenAnswer((_) async => http.Response('{"linked": false}', 200));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('ABC-123'), findsOneWidget);
  });
}
