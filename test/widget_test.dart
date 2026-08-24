import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapvoice/main.dart';
import 'package:tapvoice/ui/widgets/action_sidebar.dart';
import 'package:tapvoice/ui/widgets/gamepad_view.dart';

void main() {
  test('application root can be created', () {
    expect(const TapVoiceApp(), isA<TapVoiceApp>());
  });

  testWidgets('center controller hotspots use the artwork positions', (
    tester,
  ) async {
    final tapped = <String>[];

    await tester.binding.setSurfaceSize(const Size(1670, 924));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GamepadView(
          selectedId: null,
          boundIds: const {},
          triggeredId: null,
          playingId: null,
          playingProgress: 0,
          recording: false,
          recordingProgress: 0,
          onSelect: (button) => tapped.add(button.id),
          onButtonPressed: (button) => tapped.add('${button.id}:pressed'),
        ),
      ),
    );

    expect(find.byType(AnimatedContainer), findsNothing);

    // The base image is 1670 x 924. These are the four middle button centers.
    for (final point in const [
      Offset(676, 381),
      Offset(905, 381),
      Offset(719, 653),
      Offset(861, 653),
    ]) {
      await tester.tapAt(point);
    }

    expect(tapped, [
      'btn_minus',
      'btn_minus:pressed',
      'btn_plus',
      'btn_plus:pressed',
      'btn_star',
      'btn_star:pressed',
      'btn_home',
      'btn_home:pressed',
    ]);
  });

  testWidgets('playback uses the same pause and stop actions as recording', (
    tester,
  ) async {
    Future<void> pumpSidebar({required bool paused}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionSidebar(
              recording: false,
              playing: true,
              paused: paused,
              hasAudio: true,
              onRecord: () {},
              onPauseOrResume: () {},
              onStop: () {},
              onPlay: () {},
              onDelete: () {},
              onUpload: () {},
            ),
          ),
        ),
      );
    }

    await pumpSidebar(paused: false);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await pumpSidebar(paused: true);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });
}
