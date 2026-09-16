import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapvoice/main.dart';
import 'package:tapvoice/models/audio_mapping.dart';
import 'package:tapvoice/models/gamepad_button.dart';
import 'package:tapvoice/ui/pages/audio_list_page.dart';
import 'package:tapvoice/ui/widgets/action_sidebar.dart';
import 'package:tapvoice/ui/widgets/audio_action_dialog.dart';
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

  testWidgets('ActionSidebar shows Play and Edit when audio is present', (tester) async {
    var playTapped = false;
    var editTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionSidebar(
            playing: false,
            paused: false,
            hasAudio: true,
            onPauseOrResume: () {},
            onStop: () {},
            onPlay: () => playTapped = true,
            onEdit: () => editTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Record'), findsNothing);
    expect(find.text('Upload'), findsNothing);
    expect(find.text('Del'), findsNothing);

    await tester.tap(find.text('Play'));
    expect(playTapped, isTrue);

    await tester.tap(find.text('Edit'));
    expect(editTapped, isTrue);
  });

  testWidgets('ActionSidebar shows only Edit when no audio is present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionSidebar(
            playing: false,
            paused: false,
            hasAudio: false,
            onPauseOrResume: () {},
            onStop: () {},
            onPlay: () {},
            onEdit: () {},
          ),
        ),
      ),
    );

    expect(find.text('Play'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });

  test('AudioMapping parses legacy and multi-audio models correctly', () {
    // Legacy model format
    final legacyMap = {
      'buttonId': 'btn_a',
      'keyCode': 96,
      'audioPath': '/path/to/btn_a.m4a',
      'durationMs': 2000,
    };
    final legacyMapping = AudioMapping.fromMap(legacyMap);
    expect(legacyMapping.hasAudio, isTrue);
    expect(legacyMapping.audios.length, 1);
    expect(legacyMapping.audios.first.path, '/path/to/btn_a.m4a');
    expect(legacyMapping.audios.first.durationMs, 2000);

    // Multi-audio model format
    final multiMap = {
      'buttonId': 'btn_b',
      'keyCode': 97,
      'audios': [
        {'id': 'b_1', 'path': '/path/1.m4a', 'durationMs': 1000, 'name': 'Audio 1'},
        {'id': 'b_2', 'path': '/path/2.m4a', 'durationMs': 3000, 'name': 'Audio 2'},
      ],
    };
    final multiMapping = AudioMapping.fromMap(multiMap);
    expect(multiMapping.hasAudio, isTrue);
    expect(multiMapping.audios.length, 2);
    expect(multiMapping.audios[0].name, 'Audio 1');
    expect(multiMapping.audios[1].name, 'Audio 2');
    expect(multiMapping.durationMs, 1000);
    expect(multiMapping.audioPath, '/path/1.m4a');
  });

  testWidgets('AudioListPage renders empty state and allows tapping Add Audio', (tester) async {
    const button = GamepadButton(
      id: 'btn_a',
      label: 'A',
      keyCode: 96,
      center: Offset(0.5, 0.5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AudioListPage(
          button: button,
          mapping: null,
          onMappingChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Button A - Audios'), findsOneWidget);
    expect(find.text('0 / 10'), findsOneWidget);
    expect(find.text('No audios added yet'), findsOneWidget);
    expect(find.text('Add Audio'), findsNWidgets(2)); // in header and empty state
  });

  testWidgets('AudioListPage renders audio items and count', (tester) async {
    const button = GamepadButton(
      id: 'btn_a',
      label: 'A',
      keyCode: 96,
      center: Offset(0.5, 0.5),
    );

    const mapping = AudioMapping(
      buttonId: 'btn_a',
      keyCode: 96,
      audios: [
        AudioItem(id: 'a1', path: '/path/1.m4a', durationMs: 2400, name: 'Victory Cheer'),
        AudioItem(id: 'a2', path: '/path/2.m4a', durationMs: 5100, name: 'Defeat Sigh'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AudioListPage(
          button: button,
          mapping: mapping,
          onMappingChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Button A - Audios'), findsOneWidget);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(find.text('Victory Cheer'), findsOneWidget);
    expect(find.text('Defeat Sigh'), findsOneWidget);
    expect(find.text('Duration: 0:02'), findsOneWidget);
    expect(find.text('Duration: 0:05'), findsOneWidget);
  });

  testWidgets('AudioActionDialog displays Record and Upload for new audio slot', (tester) async {
    const button = GamepadButton(
      id: 'btn_b',
      label: 'B',
      keyCode: 97,
      center: Offset(0.5, 0.5),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudioActionDialog(
            button: button,
            audioItem: null,
          ),
        ),
      ),
    );

    expect(find.text('Button B - New Audio'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Del'), findsNothing);
  });

  testWidgets('AudioActionDialog displays Play and Del when editing existing audio', (tester) async {
    const button = GamepadButton(
      id: 'btn_b',
      label: 'B',
      keyCode: 97,
      center: Offset(0.5, 0.5),
    );

    const item = AudioItem(
      id: 'b_test',
      path: '/path/test.m4a',
      durationMs: 3200,
      name: 'Jump Sound',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AudioActionDialog(
            button: button,
            audioItem: item,
          ),
        ),
      ),
    );

    expect(find.text('Button B - Jump Sound'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Del'), findsOneWidget);
  });
}
