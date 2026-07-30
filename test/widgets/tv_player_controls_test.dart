import 'dart:async';
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart';
import 'package:reelriot_tv/widgets/tv_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:media_kit/media_kit.dart';

class MockCaffeinePlayerController extends Mock
    implements CaffeinePlayerController {}

class MockPlayer extends Mock implements Player {}

class MockPlayerStream extends Mock implements PlayerStream {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockCaffeinePlayerController mockController;
  late MockPlayer mockPlayer;
  late MockPlayerStream mockPlayerStream;
  late StreamController<bool> visibilityController;

  setUp(() {
    mockController = MockCaffeinePlayerController();
    mockPlayer = MockPlayer();
    mockPlayerStream = MockPlayerStream();
    visibilityController = StreamController<bool>.broadcast();

    // Mock controller properties
    when(() => mockController.player).thenReturn(mockPlayer);
    when(() => mockController.name).thenReturn("Test Movie");
    when(() => mockController.watchingText).thenReturn("Watching Now");
    when(() => mockController.isPlaying()).thenReturn(true);

    // Mock visibility
    when(
      () => mockController.controlsVisibilityStream,
    ).thenAnswer((_) => visibilityController.stream);
    when(
      () => mockController.toggleControlsVisibility(any()),
    ).thenAnswer((_) async {});

    // Mock event listener
    when(() => mockController.addEventsListener(any())).thenReturn(null);
    when(() => mockController.removeEventsListener(any())).thenReturn(null);

    // Mock player state
    final playerState = PlayerState(
      duration: const Duration(minutes: 10),
      position: const Duration(minutes: 5),
      buffer: const Duration(minutes: 1),
      playing: true,
    );
    when(() => mockPlayer.state).thenReturn(playerState);
    when(() => mockPlayer.stream).thenReturn(mockPlayerStream);
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

  testWidgets('Controls should be visible when visibility stream emits true', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());

    // Initially hidden
    final opacityFinder = find.byType(AnimatedOpacity);
    expect(opacityFinder, findsOneWidget);
    var animatedOpacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(animatedOpacity.opacity, 0.0);

    // Emit visible
    visibilityController.add(true);
    await tester.pumpAndSettle();

    animatedOpacity = tester.widget<AnimatedOpacity>(opacityFinder);
    expect(animatedOpacity.opacity, 1.0);
    expect(find.text("TEST MOVIE"), findsOneWidget);
  });

  testWidgets('Seek logic: Rewind/FF buttons call seekTo', (
    WidgetTester tester,
  ) async {
    when(() => mockController.seekTo(any())).thenAnswer((_) async {});

    await tester.pumpWidget(buildTestWidget());
    visibilityController.add(true);
    await tester.pumpAndSettle();

    // Navigate to FF (Right from Play/Pause)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Tap the FF icon
    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    verify(() => mockController.seekTo(any())).called(1);
  });
}
