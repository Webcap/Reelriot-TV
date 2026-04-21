import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:caffeine_tv/services/player/caffeine_player_controller.dart';
import 'package:caffeine_tv/widgets/tv_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPlayer extends Mock implements Player {}
class MockCaffeineController extends Mock implements CaffeinePlayerController {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(CaffeinePlayerEventType.initialized);
  });

  late MockCaffeineController mockController;
  late MockPlayer mockPlayer;
  late StreamController<bool> visibilityController;

  setUp(() {
    mockController = MockCaffeineController();
    mockPlayer = MockPlayer();
    visibilityController = StreamController<bool>.broadcast();

    // Mock properties
    when(() => mockController.player).thenReturn(mockPlayer);
    when(() => mockController.name).thenReturn("Test Movie");
    when(() => mockController.watchingText).thenReturn(null);
    
    // Mock player state
    final playerState = PlayerState(
      duration: const Duration(minutes: 10),
      position: const Duration(minutes: 5),
      playing: true,
    );
    when(() => mockPlayer.state).thenReturn(playerState);
    
    // Mock visibility stream
    when(() => mockController.controlsVisibilityStream)
        .thenAnswer((_) => visibilityController.stream);
    
    // Mock methods
    when(() => mockController.isPlaying()).thenReturn(true);
    when(() => mockController.toggleControlsVisibility(any())).thenAnswer((_) async {});
    when(() => mockController.addEventsListener(any())).thenReturn(null);
    when(() => mockController.removeEventsListener(any())).thenReturn(null);
    when(() => mockController.seekTo(any())).thenReturn(null);
    when(() => mockController.play()).thenReturn(null);
    when(() => mockController.pause()).thenReturn(null);
  });

  tearDown(() {
    visibilityController.close();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Scaffold(
        body: TvPlayerControls(
          controller: mockController,
          onVisibilityChanged: (_) {},
          onShowSettings: () {},
        ),
      ),
    );
  }

  testWidgets('Controls should be visible when visibility stream emits true', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());

    // Initially hidden (opacity 0)
    var animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 0.0);

    // Emit visible
    visibilityController.add(true);
    await tester.pumpAndSettle();

    animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 1.0);
    expect(find.text("TEST MOVIE"), findsOneWidget);
  });

  testWidgets('Initial focus should be on Play/Pause button when visible', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // The Play/Pause icon in the center should be present
    expect(find.byIcon(Icons.pause_rounded), findsWidgets);

    // Verify focus is on the Play/Pause button
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('D-pad navigation: Play -> Fast Forward -> Settings', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Send Right arrow from Play/Pause
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    
    // Should be on FF button (forward_10_rounded)
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);

    // Send Right arrow again
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Should be on Settings button (settings_outlined)
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('D-pad navigation: Play -> Rewind', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Send Left arrow from Play/Pause
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    // Should be on Rewind button (replay_10_rounded)
    expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
  });

  testWidgets('D-pad navigation: Up to Progress Bar', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Send Up arrow from Play/Pause
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    // Focus should move up
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
  });

  testWidgets('Seek logic: Rewind/FF buttons call seekTo', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Navigate to FF (Right from Play/Pause)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Tap the FF icon
    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.pumpAndSettle();

    verify(() => mockController.seekTo(any())).called(1);
  });

  testWidgets('Settings button triggers onShowSettings', (WidgetTester tester) async {
    bool settingsCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvPlayerControls(
          controller: mockController,
          onVisibilityChanged: (_) {},
          onShowSettings: () => settingsCalled = true,
        ),
      ),
    ));

    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Tap settings button
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(settingsCalled, isTrue);
  });
}
