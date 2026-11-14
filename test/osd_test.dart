import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/bar_theme.dart';
import 'package:remya_bar/features/osd/osd_controller.dart';
import 'package:remya_bar/features/osd/osd_slider.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_ui/remya_ui.dart';

void main() {
  group('OsdCapsuleSlider', () {
    Widget wrap(OsdCapsuleSlider slider) => MaterialApp(
      theme: barTheme(const RemyaTheme().theme(.dark)),
      home: Scaffold(body: Center(child: slider)),
    );

    testWidgets(
      'renders Volume Normal, Muted, and Boost regimes with spec geometry',
      (tester) async {
        // 1. Volume Normal 65%: no range tag, 100% dot marker visible, text in Inactive track
        await tester.pumpWidget(
          wrap(const OsdCapsuleSlider(type: .volume, value: 65)),
        );
        expect(find.text('65%'), findsOneWidget);
        expect(find.text('Boost'), findsNothing);
        expect(find.text('Gamma'), findsNothing);
        expect(tester.getSize(find.byType(OsdCapsuleSlider)), osdSize);

        // 2. Volume Muted (pre-mute 65%): shows 'Muted' in Inactive track
        await tester.pumpWidget(
          wrap(
            const OsdCapsuleSlider(
              type: .volume,
              value: 65,
              muted: true,
              preMuteValue: 65,
            ),
          ),
        );
        expect(find.text('Muted'), findsOneWidget);
        expect(find.text('65%'), findsNothing);
        expect(find.text('Boost'), findsNothing);

        // 3. Volume Boost 130%: shows 'Boost' range tag and '130%'
        await tester.pumpWidget(
          wrap(const OsdCapsuleSlider(type: .volume, value: 130)),
        );
        expect(find.text('130%'), findsOneWidget);
        expect(find.text('Boost'), findsOneWidget);

        // 4. Volume Boost 150% has a full boost track and no handle.
        await tester.pumpWidget(
          wrap(const OsdCapsuleSlider(type: .volume, value: 150)),
        );
        expect(find.text('150%'), findsOneWidget);
        expect(find.text('Boost'), findsOneWidget);
        expect(find.byKey(const ValueKey('osd-handle')), findsNothing);
      },
    );

    testWidgets('renders Brightness and Gamma regimes with range tag clamping', (
      tester,
    ) async {
      // Brightness 85%: no range tag, text in Active track
      await tester.pumpWidget(
        wrap(const OsdCapsuleSlider(type: .brightness, value: 85)),
      );
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('Software brightness'), findsNothing);
      expect(find.text('Boost'), findsNothing);

      // Software brightness uses its own label and keeps the same readout edge.
      final readoutRight = tester.getTopRight(find.text('85%')).dx;
      await tester.pumpWidget(
        wrap(const OsdCapsuleSlider(type: .gamma, value: 65)),
      );
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Software brightness'), findsOneWidget);
      expect(
        tester.getTopRight(find.text('65%')).dx,
        closeTo(readoutRight, .01),
      );

      // Gamma 100% means the software dimming filter is off.
      await tester.pumpWidget(
        wrap(const OsdCapsuleSlider(type: .gamma, value: 100)),
      );
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Dimming off'), findsOneWidget);
    });
  });

  testWidgets(
    'volume handle and readout stay aligned across the boost boundary and mute',
    (tester) async {
      final handle = find.byKey(const ValueKey('osd-handle'));
      double? markerX;
      double? previousX;
      double? readoutRight;
      for (final percent in [60, 99, 100, 101, 130]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: OsdCapsuleSlider(type: .volume, value: percent),
            ),
          ),
        );
        final x = tester.getCenter(handle).dx;
        final right = tester.getTopRight(find.text('$percent%')).dx;
        readoutRight ??= right;
        expect(right, closeTo(readoutRight, .01));
        if (previousX != null) expect(x, greaterThan(previousX));
        previousX = x;
        if (percent == 60) {
          markerX = tester
              .getCenter(find.byKey(const ValueKey('osd-100-marker')))
              .dx;
        }
        if (percent == 100) expect(x, closeTo(markerX!, .01));
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: OsdCapsuleSlider(
              type: .volume,
              value: 130,
              preMuteValue: 130,
              muted: true,
            ),
          ),
        ),
      );
      expect(tester.getCenter(handle).dx, closeTo(previousX!, .01));
      expect(
        tester.getTopRight(find.text('Muted')).dx,
        closeTo(readoutRight!, .01),
      );
      expect(find.text('Boost'), findsNothing);
    },
  );

  group('OsdController', () {
    late _FakeSettingsClient settings;
    late OsdController controller;

    setUp(() async {
      settings = _FakeSettingsClient();
      controller = OsdController(
        settings: settings,
        timeout: const Duration(milliseconds: 80),
      )..start(output: 'eDP-1');
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      controller.dispose();
      await settings.close();
    });

    test('initial load stays hidden and passive sound changes show and auto-dismiss OSD', () async {
      expect(controller.state, isNull);

      settings.emitSound(percent: 75, muted: false);
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.state,
        const OsdState(type: .volume, value: 75, preMuteValue: 75),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(controller.state, isNull);
    });

    test('volume shortcuts respect configured step size, boost up to 150%, and preserve pre-mute position', () async {
      settings.osdPrefs = const BarOsdPreferences(
        volumeStep: 10,
        brightnessStep: 5,
        gammaMin: 15,
      );
      settings.changesController.add((
        topic: barOsdSettingId,
        value: <String, dynamic>{'value': 10},
      ));
      await Future<void>.delayed(Duration.zero);

      await controller.handleShortcut('VolumeUp');
      expect(
        controller.state,
        const OsdState(type: .volume, value: 60, preMuteValue: 60),
      );

      await controller.handleShortcut('VolumeMute');
      expect(
        controller.state,
        const OsdState(type: .volume, value: 60, muted: true, preMuteValue: 60),
      );

      // VolumeUp while muted unmutes and steps up
      await controller.handleShortcut('VolumeUp');
      expect(
        controller.state,
        const OsdState(type: .volume, value: 70, preMuteValue: 70),
      );
    });

    test('volume shortcuts stop at the configured maximum volume', () async {
      settings.osdPrefs = const BarOsdPreferences(
        volumeStep: 10,
        volumeMax: 110,
      );
      settings.changesController.add((
        topic: barOsdSettingId,
        value: <String, dynamic>{'value': 110},
      ));
      settings.emitSound(percent: 95, muted: false);
      await Future<void>.delayed(Duration.zero);

      await controller.handleShortcut('VolumeUp');
      await controller.handleShortcut('VolumeUp');
      expect(settings.volumePercent, 110);
      expect(
        controller.state,
        const OsdState(type: .volume, value: 110, preMuteValue: 110, max: 110),
      );
    });

    test('zero volume and mute are one state', () async {
      settings.osdPrefs = const BarOsdPreferences(volumeStep: 10);
      settings.changesController.add((
        topic: barOsdSettingId,
        value: <String, dynamic>{'value': 10},
      ));
      settings.emitSound(percent: 10, muted: false);
      await Future<void>.delayed(Duration.zero);

      // Stepping down to 0 also mutes.
      await controller.handleShortcut('VolumeDown');
      expect((settings.volumePercent, settings.volumeMuted), (0, true));
      expect(controller.state?.muted, isTrue);

      // Unmuting from 0 restores one step instead of a silent unmuted state.
      await controller.handleShortcut('VolumeMute');
      expect((settings.volumePercent, settings.volumeMuted), (10, false));

      // An external 0 without the mute flag is shown and toggled as muted.
      settings.emitSound(percent: 0, muted: false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state?.muted, isTrue);
      await controller.handleShortcut('VolumeUp');
      expect((settings.volumePercent, settings.volumeMuted), (10, false));
    });

    test('brightness shortcuts transition between hardware backlight and hyprsunset gamma', () async {
      settings.emitBrightness(percent: 6);
      await Future<void>.delayed(Duration.zero);
      await controller.handleShortcut('BrightnessDown');
      expect(controller.state, const OsdState(type: .brightness, value: 1));
      expect(settings.brightnessPercent, 1);
      expect(settings.gammaPercent, 100);

      // At hardware floor (1%), BrightnessDown transitions into Gamma dimming
      await controller.handleShortcut('BrightnessDown');
      expect(controller.state, const OsdState(type: .gamma, value: 95));
      expect(settings.gammaPercent, 95);

      await controller.handleShortcut('BrightnessDown');
      expect(controller.state, const OsdState(type: .gamma, value: 90));
      expect(settings.gammaPercent, 90);

      // BrightnessUp brings Gamma back to 100% before increasing hardware backlight
      await controller.handleShortcut('BrightnessUp');
      expect(controller.state, const OsdState(type: .gamma, value: 95));
      await controller.handleShortcut('BrightnessUp');
      expect(controller.state, const OsdState(type: .gamma, value: 100));

      // Now that Gamma is 100%, BrightnessUp increases hardware backlight
      await controller.handleShortcut('BrightnessUp');
      expect(controller.state, const OsdState(type: .brightness, value: 6));
      expect(settings.brightnessPercent, 6);
    });

    test('queued hardware keys use confirmed readbacks and do not show failed targets', () async {
      settings.failBrightnessWrite = true;
      await controller.handleShortcut('BrightnessDown');
      expect(controller.state, isNull);
      expect(settings.brightnessPercent, 50);
      settings.failBrightnessWrite = false;
      await Future.wait([
        controller.handleShortcut('BrightnessDown'),
        controller.handleShortcut('BrightnessDown'),
      ]);
      expect(controller.state, const OsdState(type: .brightness, value: 40));
      expect(settings.brightnessPercent, 40);
      expect(settings.gammaPercent, 100);
    });

    test('held brightness key coalesces writes without skipping the hardware floor', () async {
      settings.emitBrightness(percent: 16);
      await Future<void>.delayed(Duration.zero);
      await Future.wait([
        for (var index = 0; index < 5; index++)
          controller.handleShortcut('BrightnessDown'),
      ]);
      expect(settings.brightnessWrites, ['11', '1', '90']);
      expect(settings.brightnessPercent, 1);
      expect(controller.state, const OsdState(type: .gamma, value: 90));
    });

    test(
      'service reconnect reloads the baseline without opening the popup',
      () async {
        settings.owners.add(false);
        await Future<void>.delayed(Duration.zero);
        settings.brightnessPercent = 25;
        settings.owners.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, isNull);
        await controller.handleShortcut('BrightnessUp');
        expect(controller.state, const OsdState(type: .brightness, value: 30));
      },
    );

    test('a late brightness read for the old output cannot overwrite the new output', () async {
      final pending = Completer<Map<String, dynamic>>();
      settings.pendingBrightness = pending;
      controller.updateOutput('DP-1');
      controller.updateOutput('eDP-1');
      pending.complete({
        'output': 'DP-1',
        'percent': 80,
        'backend': 'ddc',
        'reason': '',
      });
      await Future<void>.delayed(Duration.zero);
      await controller.handleShortcut('BrightnessUp');
      expect(controller.state, const OsdState(type: .brightness, value: 55));
    });
  });
}

class _FakeSettingsClient extends SettingsClient {
  final changesController = StreamController<SettingsChange>.broadcast();
  final owners = StreamController<bool>.broadcast();
  BarOsdPreferences osdPrefs = const BarOsdPreferences(
    volumeStep: 5,
    brightnessStep: 5,
  );
  int volumePercent = 50;
  bool volumeMuted = false;
  int brightnessPercent = 50;
  bool failBrightnessWrite = false;
  int gammaPercent = 100;
  final brightnessWrites = <String>[];
  Completer<Map<String, dynamic>>? pendingBrightness;

  @override
  Stream<SettingsChange> get changes => changesController.stream;

  @override
  Stream<bool> get serviceAvailableChanges => owners.stream;

  void emitSound({required int percent, required bool muted}) {
    volumePercent = percent;
    volumeMuted = muted;
    changesController.add((topic: 'sound', value: _soundPayload()));
  }

  void emitBrightness({required int percent}) {
    brightnessPercent = percent;
    changesController.add((
      topic: 'display-brightness',
      value: {
        'outputs': [
          {
            'output': 'eDP-1',
            'percent': brightnessPercent,
            'backend': 'backlight',
            'reason': '',
          },
        ],
      },
    ));
  }

  Map<String, dynamic> _soundPayload() => {
    'available': true,
    'system': {
      'default_output': 'speaker',
      'devices': [
        {
          'name': 'speaker',
          'direction': 'output',
          'preferences': {
            'channels': [(volumePercent * 65536 / 100).round()],
            'muted': volumeMuted,
          },
        },
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> args = const [],
  ]) async {
    if (method == 'Get') {
      final key = args.single;
      if (key == 'display-brightness:DP-1' && pendingBrightness != null) {
        return pendingBrightness!.future;
      }
      return switch (key) {
        barOsdSettingId => {
          'value': {
            'volume-step': osdPrefs.volumeStep,
            'volume-max': osdPrefs.volumeMax,
            'brightness-step': osdPrefs.brightnessStep,
            'gamma-min': osdPrefs.gammaMin,
          },
          'revision': 'a' * 64,
        },
        'sound' => _soundPayload(),
        'display-brightness:eDP-1' => {
          'output': 'eDP-1',
          'percent': brightnessPercent,
          'backend': 'backlight',
          'reason': '',
        },
        'display-gamma' => {
          'gamma': gammaPercent,
          'running': gammaPercent < 100,
          'available': true,
        },
        _ => <String, dynamic>{},
      };
    }
    if (method == 'Set') {
      final key = args[0];
      final raw = args[1];
      switch (key) {
        case soundOutputVolumeSettingId:
          final decoded = jsonDecode(raw) as Map;
          volumePercent = (decoded['percent'] as num).round();
          return _soundPayload();
        case soundOutputMutedSettingId:
          final decoded = jsonDecode(raw) as Map;
          volumeMuted = decoded['muted'] == true;
          return _soundPayload();
        case 'display-brightness:eDP-1':
          if (failBrightnessWrite) throw StateError('Backlight write rejected');
          brightnessWrites.add(raw);
          brightnessPercent = int.parse(raw);
          return {
            'output': 'eDP-1',
            'percent': brightnessPercent,
            'outputs': [
              {'output': 'eDP-1', 'percent': brightnessPercent},
            ],
          };
        case 'display-gamma':
          brightnessWrites.add(raw);
          gammaPercent = int.parse(raw);
          return {
            'gamma': gammaPercent,
            'running': gammaPercent < 100,
            'available': true,
          };
      }
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> close() async {
    await changesController.close();
    await owners.close();
  }
}
