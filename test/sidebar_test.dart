import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/settings/remya_settings_installed.dart';
import 'package:remya_bar/features/sidebar/right_sidebar.dart';
import 'package:remya_bar/features/sidebar/sidebar_backend.dart';
import 'package:remya_bar/src/rust/system_bridge/frb_generated.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_display.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';

void main() {
  debugRemyaSettingsInstalled = true;
  group('SidebarBackend', () {
    late _Settings settings;
    late SidebarBackend backend;
    setUp(() async {
      SystemRustLib.initMock(api: _SidebarApi());
      settings = _Settings();
      backend = SidebarBackend(settings: settings)..open('eDP-1');
      await _flush();
    });
    tearDown(() {
      backend.dispose();
      SystemRustLib.dispose();
    });

    Future<void> volume(
      num percent, {
      String direction = 'output',
      String target = 'speaker',
    }) => backend.perform({
      'action': 'sidebar.$direction-volume',
      'target': target,
      'value': percent,
    }, 'eDP-1');

    test(
      'FIFO writes coalesce only queued volume for the same target',
      () async {
        final original = settings.snapshots['sound'];
        final first = volume(30);
        final second = volume(50);
        final wifi = backend.perform({
          'action': 'sidebar.wifi',
          'value': false,
        }, null);
        final latest = volume(80);
        final input = volume(40, direction: 'input', target: 'mic');
        var completed = false;
        unawaited(second.then((_) => completed = true));
        expect(settings.writes, hasLength(1));
        expect(_percent(backend.data), closeTo(80, .002));
        expect(_percent({'sound': original}), closeTo(20, .002));
        settings.writes[0].result.complete(_sound(30));
        await first;
        expect(completed, isFalse);
        expect(settings.writes.map((write) => write.id), [
          'sound.output-volume',
          'sound.output-volume',
        ]);
        expect(jsonDecode(settings.writes[1].value)['percent'], 80);
        expect(_percent(backend.data), closeTo(80, .002));
        expect(settings.soundReads, 1);
        settings.writes[1].result.complete(_sound(79));
        await Future.wait([second, latest]);
        expect(_percent(backend.data), closeTo(79, .002));
        settings.writes[2].result.complete({'wifi_enabled': false});
        await wifi;
        expect(settings.writes[3].id, 'sound.input-volume');
        expect(jsonDecode(settings.writes[3].value)['name'], 'mic');
        settings.snapshots['sound'] = _sound(79);
        settings.writes[3].result.complete(_sound(79));
        await input;
        await _flush();
        expect(settings.soundReads, 2);
      },
    );

    for (final action in ['input-volume', 'brightness']) {
      test('$action coalesces queued values', () async {
        backend.close();
        Future<void> send(num value) => backend.perform({
          'action': 'sidebar.$action',
          'target': action == 'brightness' ? 'eDP-1' : 'mic',
          'value': value,
        }, 'eDP-1');
        final first = send(30);
        final second = send(50);
        final latest = send(80);
        expect(settings.writes, hasLength(1));
        settings.writes[0].result.complete(
          action == 'brightness' ? {'percent': 30} : _sound(30),
        );
        await first;
        expect(settings.writes, hasLength(2));
        final request = settings.writes[1].value;
        expect(
          action == 'brightness' ? request : jsonDecode(request)['percent'],
          action == 'brightness' ? '80' : 80,
        );
        settings.writes[1].result.complete(
          action == 'brightness' ? {'percent': 80} : _sound(80),
        );
        await Future.wait([second, latest]);
      });
    }

    test('output boost and both directions of the brightness crossover reach Settings', () async {
      backend.close();
      final boosted = volume(130);
      expect(_percent(backend.data), closeTo(130, .002));
      expect(jsonDecode(settings.writes.single.value)['percent'], 130);
      settings.writes.single.result.complete(_sound(130));
      await boosted;

      Future<void> brightness(Object value) => backend.perform({
        'action': 'sidebar.brightness',
        'target': 'eDP-1',
        'value': value,
      }, 'eDP-1');
      final dim = brightness({'gamma': 75});
      expect(settings.writes.last.id, 'display-brightness:eDP-1');
      expect(settings.writes.last.value, '1');
      settings.writes.last.result.complete({'percent': 1});
      await _flush();
      expect(settings.writes.last.id, displayGammaSettingId);
      expect(settings.writes.last.value, '75');
      settings.writes.last.result.complete({'gamma': 75});
      await dim;
      expect((backend.data['brightness'] as Map)['gamma'], 75);

      final brighter = brightness(40);
      expect(settings.writes.last.id, displayGammaSettingId);
      expect(settings.writes.last.value, '100');
      settings.writes.last.result.complete({'gamma': 100});
      await _flush();
      expect(settings.writes.last.id, 'display-brightness:eDP-1');
      expect(settings.writes.last.value, '40');
      settings.writes.last.result.complete({'percent': 40});
      await brighter;
      expect((backend.data['brightness'] as Map)['percent'], 40);
    });

    test('volume coalescing keeps different device targets separate', () async {
      backend.close();
      final first = volume(30);
      final second = volume(50);
      final other = volume(40, target: 'headphones');
      final latest = volume(80);
      settings.writes[0].result.complete(_sound(30));
      await first;
      expect(jsonDecode(settings.writes[1].value), {
        'name': 'speaker',
        'percent': 80,
      });
      settings.writes[1].result.complete(_sound(80));
      await Future.wait([second, latest]);
      expect(jsonDecode(settings.writes[2].value), {
        'name': 'headphones',
        'percent': 40,
      });
      settings.writes[2].result.complete(_sound(80));
      await other;
    });

    test(
      'coalesced errors reach both callers, the queue continues and reconciles',
      () async {
        final first = volume(30);
        final second = volume(50);
        final latest = volume(80);
        final firstError = expectLater(first, throwsStateError);
        final secondError = expectLater(second, throwsStateError);
        final latestError = expectLater(latest, throwsStateError);
        settings.writes[0].result.completeError(StateError('first failed'));
        await firstError;
        expect(settings.writes, hasLength(2));
        expect(settings.soundReads, 1);
        settings.writes[1].result.complete({'error': 'last failed'});
        await Future.wait([secondError, latestError]);
        await _flush();
        expect(settings.soundReads, 2);
        expect(_percent(backend.data), closeTo(20, .002));
      },
    );

    test(
      'stale reads and change signals cannot overwrite pending predictions',
      () async {
        final read = settings.soundRead = Completer<Map<String, dynamic>>();
        settings.updates.add((topic: 'sound', value: {}));
        await _flush();
        final write = volume(75);
        final dark = backend.perform({
          'action': 'sidebar.dark',
          'value': true,
        }, null);
        settings.updates.add((
          topic: 'theme',
          value: {
            'theme': {'theme_mode': 'light'},
          },
        ));
        read.complete(_sound(10));
        await _flush();
        expect(_percent(backend.data), closeTo(75, .002));
        expect(
          ((backend.data['theme'] as Map)['theme'] as Map)['theme_mode'],
          'dark',
        );
        expect(settings.soundReads, 2);
        settings.writes[0].result.complete(_sound(75));
        await write;
        backend.close();
        settings.writes[1].result.complete({
          'theme': {'theme_mode': 'dark'},
        });
        await dark;
      },
    );

    test('zero volume mutes and unmuting silence restores one step', () async {
      Map<String, dynamic> silent({required bool muted}) {
        final sound = _sound(0);
        for (final device in (sound['system'] as Map)['devices'] as List) {
          (device as Map)['preferences']['muted'] = muted;
        }
        return sound;
      }

      Object? written(int index) => jsonDecode(settings.writes[index].value);

      final zero = volume(0);
      expect(_preferences(backend.data, 'output')['muted'], isTrue);
      settings.writes[0].result.complete(silent(muted: false));
      await _flush();
      expect(settings.writes[1].id, 'sound.output-muted');
      expect(written(1), {'name': 'speaker', 'muted': true});
      settings.writes[1].result.complete(silent(muted: true));
      await zero;

      settings.snapshots['sound'] = silent(muted: true);
      final unmute = backend.perform({
        'action': 'sidebar.output-muted',
        'target': 'speaker',
        'value': false,
      }, 'eDP-1');
      await _flush();
      expect(settings.writes[2].id, 'sound.output-volume');
      expect(written(2), {'name': 'speaker', 'percent': 5});
      settings.writes[2].result.complete(silent(muted: true));
      await _flush();
      expect(written(3), {'name': 'speaker', 'muted': false});
      settings.writes[3].result.complete(_sound(5));
      await unmute;
    });

    final predictions =
        <
          ({
            Map args,
            String key,
            Object? Function(Map) select,
            Object? expected,
          })
        >[
          (
            args: {
              'action': 'sidebar.output-volume',
              'target': 'speaker',
              'value': 65,
            },
            key: 'sound',
            select: (data) => _percent(data).round(),
            expected: 65,
          ),
          (
            args: {
              'action': 'sidebar.input-volume',
              'target': 'mic',
              'value': 65,
            },
            key: 'sound',
            select: (data) => _percent(data, direction: 'input').round(),
            expected: 65,
          ),
          (
            args: {
              'action': 'sidebar.output-muted',
              'target': 'speaker',
              'value': true,
            },
            key: 'sound',
            select: (data) => _preferences(data, 'output')['muted'],
            expected: true,
          ),
          (
            args: {
              'action': 'sidebar.input-muted',
              'target': 'mic',
              'value': true,
            },
            key: 'sound',
            select: (data) => _preferences(data, 'input')['muted'],
            expected: true,
          ),
          (
            args: {
              'action': 'sidebar.brightness',
              'target': 'eDP-1',
              'value': 65,
            },
            key: 'brightness',
            select: (data) => (data['brightness'] as Map)['percent'],
            expected: 65,
          ),
          (
            args: {'action': 'sidebar.wifi', 'value': false},
            key: 'network',
            select: (data) => (data['network'] as Map)['wifi_enabled'],
            expected: false,
          ),
          (
            args: {
              'action': 'sidebar.bluetooth',
              'value': {'adapter': 'hci0', 'enabled': true},
            },
            key: 'bluetooth',
            select: (data) => ((data['bluetooth'] as Map)['adapters'] as List)
                .first['powered'],
            expected: true,
          ),
          (
            args: {'action': 'sidebar.night-light', 'value': true},
            key: 'night-light',
            select: (data) => (data['night-light'] as Map)['enabled'],
            expected: true,
          ),
          (
            args: {'action': 'sidebar.keep-awake', 'value': true},
            key: 'keep-awake',
            select: (data) => (data['keep-awake'] as Map)['value'],
            expected: true,
          ),
          (
            args: {'action': 'sidebar.dark', 'value': true},
            key: 'theme',
            select: (data) =>
                ((data['theme'] as Map)['theme'] as Map)['theme_mode'],
            expected: 'dark',
          ),
          (
            args: {'action': 'sidebar.profile', 'value': 'power-saver'},
            key: 'power',
            select: (data) =>
                ((data['power'] as Map)['system'] as Map)['profile'],
            expected: 'power-saver',
          ),
        ];
    for (final prediction in predictions) {
      test(
        '${prediction.args['action']} predicts immutably then accepts authoritative state',
        () async {
          backend.close();
          final original = backend.data;
          final before = jsonEncode(original);
          var notifications = 0;
          backend.addListener(() => notifications++);
          final write = backend.perform(prediction.args, 'eDP-1');
          expect(prediction.select(backend.data), prediction.expected);
          expect(notifications, 1);
          expect(jsonEncode(original), before);
          expect(
            identical(original[prediction.key], backend.data[prediction.key]),
            isFalse,
          );
          final result = <String, dynamic>{'authoritative': true};
          if (prediction.key == 'brightness') result['percent'] = 64;
          settings.writes.single.result.complete(result);
          await write;
          expect(
            prediction.key == 'brightness'
                ? (backend.data['brightness'] as Map)['percent']
                : (backend.data[prediction.key] as Map)['authoritative'],
            prediction.key == 'brightness' ? 64 : true,
          );
        },
      );
    }
  });

  Future<void> showSidebar(
    WidgetTester tester,
    List<Map<String, Object?>> actions, {
    Map<String, Object?> overrides = const {},
    Future<void> Function(Map<String, Object?>)? onAction,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 663);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: RightSidebar(
          data: {
            'account': {'username': 'Tester'},
            'uptimeSeconds': 3600,
            'layout': ['internet', 'power', 'audio', 'caffeine'],
            'brightness': {'output': 'eDP-1', 'percent': 50},
            'network': {
              'available': true,
              'wifi_hardware_enabled': true,
              'writable': true,
              'wifi_enabled': true,
              'adapter': 'wlan0',
              'devices': [
                {
                  'interface': 'wlan0',
                  'networks': [
                    {'ssid': 'Nearby', 'signal': 90, 'security': 'open'},
                    {
                      'ssid': 'Home',
                      'signal': 60,
                      'in_use': true,
                      'known_uuid': 'wifi-id',
                      'security': 'wpa2',
                    },
                  ],
                },
              ],
            },
            ...overrides,
          },
          onAction: onAction ?? (action) async => actions.add(action),
          onHeight: (_) {},
        ),
      ),
    );
  }

  testWidgets('compact toggles send the inverse of live Settings state', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(
      tester,
      actions,
      overrides: {
        'layout': ['caffeine', 'dark', 'mic-mute', 'dnd-quick', 'airplane'],
        'keep-awake': {'value': true},
        'notification-dnd': {'value': true},
        'airplane': {'available': true, 'enabled': false},
        'theme': {
          'theme': {'theme_mode': 'light'},
        },
        'sound': {
          'system': {
            'default_input': 'mic',
            'devices': [
              {
                'name': 'mic',
                'direction': 'input',
                'preferences': {'muted': true},
              },
            ],
          },
        },
      },
    );
    for (final title in [
      'Keep awake',
      'Dark mode',
      'Mic mute',
      'Do Not Disturb',
      'Airplane mode',
    ]) {
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == title),
      );
      await tester.pumpAndSettle();
    }
    expect(actions, [
      {'action': 'sidebar.keep-awake', 'target': null, 'value': false},
      {'action': 'sidebar.dark', 'target': null, 'value': true},
      {'action': 'sidebar.input-muted', 'target': 'mic', 'value': false},
      {'action': 'sidebar.dnd', 'target': null, 'value': false},
      {'action': 'sidebar.airplane', 'target': null, 'value': true},
    ]);
  });

  testWidgets('Wi-Fi sorts connected first and dispatches disconnect', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.text('Internet'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Home')).dy,
      lessThan(tester.getTopLeft(find.text('Nearby')).dy),
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    expect(actions.map((action) => action['action']), [
      'sidebar.wifi-scan',
      'sidebar.wifi-disconnect',
    ]);
  });

  testWidgets('power actions expire and require a second click', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.byTooltip('Power'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shut down'));
    await tester.pump();
    expect(find.text('Confirm?'), findsOneWidget);
    expect(actions, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Shut down'), findsOneWidget);
    await tester.tap(find.text('Shut down'));
    await tester.pump();
    await tester.tap(find.text('Confirm?'));
    expect(actions.single['value'], 'shutdown');
  });

  testWidgets('editing sends previous and new tile order on Escape', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.byTooltip('Edit layout'));
    await tester.pumpAndSettle();
    final smallTile = find
        .ancestor(
          of: find.byIcon(Icons.coffee_rounded),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getSize(smallTile), const Size(68, 52));
    await tester.tap(find.byTooltip('Hide Internet').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(actions.single, {
      'action': 'sidebar.layout',
      'target': ['internet', 'power', 'audio', 'caffeine'],
      'value': ['power', 'audio', 'caffeine'],
    });
  });

  testWidgets(
    'slider throttles leading and trailing writes and holds release',
    (tester) async {
      final actions = <Map<String, Object?>>[];
      await showSidebar(tester, actions);
      Slider slider() => tester.widget<Slider>(find.byType(Slider).first);
      slider().onChangeStart!(50);
      slider().onChanged!(60);
      slider().onChanged!(70);
      expect(actions.map((action) => action['value']), [60]);
      await tester.pump(const Duration(milliseconds: 59));
      expect(actions, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(actions.map((action) => action['value']), [60, 70]);
      slider().onChanged!(80);
      slider().onChangeEnd!(85);
      await tester.pump();
      expect(actions.map((action) => action['value']), [60, 70, 85]);
      expect(slider().value, 85);
      await tester.pump(const Duration(milliseconds: 1499));
      expect(slider().value, 85);
      await tester.pump(const Duration(milliseconds: 1));
      expect(slider().value, 50);

      slider().onChangeStart!(50);
      slider().onChanged!(80);
      slider().onChangeEnd!(80);
      await tester.pump();
      expect(slider().value, 80);
      await showSidebar(
        tester,
        actions,
        overrides: {
          'brightness': {'output': 'eDP-1', 'percent': 79.6},
        },
      );
      expect(slider().value, 79.6);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('sidebar exposes boost and software brightness ranges', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(
      tester,
      actions,
      overrides: {
        'brightness': {'output': 'eDP-1', 'percent': 1, 'gamma': 75},
        'osd': const BarOsdPreferences(gammaMin: 15).toJson(),
        'sound': _sound(130),
      },
    );
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders[0].min, -84);
    expect(find.text('75%'), findsOneWidget);
    sliders[0].onChanged!(-84);
    expect(actions.last['value'], {'gamma': 15});
    expect(sliders[1].max, 150);
    expect(find.text('130%'), findsOneWidget);
    sliders[1].onChanged!(150);
    expect(actions.last['value'], 150);
  });

  testWidgets('volume slider honors the ceiling and shows zero as muted', (
    tester,
  ) async {
    await showSidebar(
      tester,
      [],
      overrides: {
        'osd': const BarOsdPreferences(volumeMax: 120).toJson(),
        'sound': _sound(0),
      },
    );
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders[1].max, 120);
    // Speaker and microphone are both at 0.
    expect(find.text('Muted'), findsNWidgets(2));
  });

  testWidgets(
    'quick controls stay enabled while actions overlap and show errors',
    (tester) async {
      final writes = <Completer<void>>[];
      final actions = <Map<String, Object?>>[];
      await showSidebar(
        tester,
        actions,
        overrides: {
          'layout': ['caffeine', 'dark'],
          'keep-awake': {'value': false},
          'theme': {
            'theme': {'theme_mode': 'light'},
          },
        },
        onAction: (action) {
          actions.add(action);
          final result = Completer<void>();
          writes.add(result);
          return result.future;
        },
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Keep awake',
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Dark mode'),
      );
      await tester.pump();
      expect(actions.map((action) => action['action']), [
        'sidebar.keep-awake',
        'sidebar.dark',
      ]);
      expect(
        tester.widget<Slider>(find.byType(Slider).first).onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Edit layout',
              ),
            )
            .onPressed,
        isNull,
      );
      writes.first.complete();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Edit layout',
              ),
            )
            .onPressed,
        isNull,
      );
      writes.last.completeError(
        PlatformException(code: 'failed', message: 'Write failed'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Write failed'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Edit layout',
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('power menu includes Suspend with two-step confirmation', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(tester, actions);
    await tester.tap(find.byTooltip('Power'));
    await tester.pump();
    final suspend = find.text('Suspend');
    expect(suspend, findsOneWidget);
    await tester.tap(suspend);
    await tester.pump();
    expect(actions, isEmpty);
    await tester.tap(find.text('Confirm?'));
    await tester.pump();
    expect(actions, [
      {'action': 'sidebar.session', 'value': 'suspend', 'target': null},
    ]);
  });

  testWidgets('capture quick tiles send sidebar.capture targets', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await showSidebar(
      tester,
      actions,
      overrides: {
        'layout': ['screenshot', 'record', 'picker'],
      },
    );
    for (final title in ['Screenshot', 'Screen record', 'Color picker']) {
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == title),
      );
      await tester.pump();
    }
    expect(actions, [
      {'action': 'sidebar.capture', 'value': null, 'target': 'screenshot'},
      {'action': 'sidebar.capture', 'value': null, 'target': 'record'},
      {'action': 'sidebar.capture', 'value': null, 'target': 'picker'},
    ]);
  });

  testWidgets(
    'detail view pins top controls and bottom actions outside scrollable list',
    (tester) async {
      await showSidebar(
        tester,
        [],
        overrides: {
          'network': {
            'available': true,
            'wifi_hardware_enabled': true,
            'writable': true,
            'wifi_enabled': true,
            'adapter': 'wlan0',
            'devices': [
              {
                'interface': 'wlan0',
                'networks': [
                  for (var i = 1; i <= 15; i++)
                    {'ssid': 'Net-$i', 'signal': 90 - i, 'security': 'wpa2'},
                ],
              },
            ],
          },
        },
      );
      await tester.tap(find.text('Internet'));
      await tester.pump();
      final header = find.text('Available networks');
      final startX = tester.getTopLeft(header).dx;
      await tester.pump(const Duration(milliseconds: 100));
      final midX = tester.getTopLeft(header).dx;
      await tester.pumpAndSettle();
      final endX = tester.getTopLeft(header).dx;
      expect(startX, greaterThan(midX));
      expect(midX, greaterThan(endX));
      final headerBottom = tester
          .getBottomLeft(find.text('Available networks'))
          .dy;
      final listRect = tester.getRect(find.byType(SingleChildScrollView));
      final footerTop = tester.getTopLeft(find.text('Network settings')).dy;
      expect(headerBottom, lessThanOrEqualTo(listRect.top));
      expect(listRect.bottom, lessThanOrEqualTo(footerTop));
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Map _preferences(Map data, String direction) =>
    (((data['sound'] as Map)['system'] as Map)['devices'] as List).firstWhere(
          (device) => device['direction'] == direction,
        )['preferences']
        as Map;

double _percent(Map data, {String direction = 'output'}) =>
    ((_preferences(data, direction)['channels'] as List).reduce(
      (a, b) => (a as int) > (b as int) ? a : b,
    ) as int) *
    100 /
    65536;

Map<String, dynamic> _sound(num percent) => {
  'system': {
    'default_output': 'speaker',
    'default_input': 'mic',
    'devices': [
      for (final direction in ['output', 'input'])
        {
          'direction': direction,
          'name': direction == 'output' ? 'speaker' : 'mic',
          'preferences': {
            'channels': [
              (percent * 65536 / 100).round(),
              (percent * 65536 / 200).round(),
            ],
            'muted': false,
          },
        },
    ],
  },
};

class _Settings extends SettingsClient {
  final updates = StreamController<SettingsChange>();
  final writes =
      <({String id, String value, Completer<Map<String, dynamic>> result})>[];
  final snapshots = <String, Map<String, dynamic>>{
    'sound': _sound(20),
    'network': {'wifi_enabled': true},
    'bluetooth': {
      'adapters': [
        {'id': 'hci0', 'powered': false},
        {'id': 'hci1', 'powered': false},
      ],
    },
    'night-light': {'enabled': false},
    'power.keep-awake': {'value': false},
    'theme': {
      'theme': {'theme_mode': 'light'},
    },
    'power': {
      'system': {'profile': 'balanced'},
    },
    'display-brightness:eDP-1': {'output': 'eDP-1', 'percent': 50},
    displayGammaSettingId: {'gamma': 100},
    barOsdSettingId: {
      'revision': 'a' * 64,
      'value': {
        'volume-step': 5,
        'volume-max': 150,
        'brightness-step': 5,
        'gamma-min': 15,
      },
    },
    barSidebarLayoutSettingId: {
      'revision': 'a' * 64,
      'value': ['internet', 'power'],
    },
  };
  Completer<Map<String, dynamic>>? soundRead;
  int soundReads = 0;

  @override
  Stream<SettingsChange> get changes => updates.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Get') {
      if (arguments.single == 'sound') {
        soundReads++;
        if (soundRead case final read?) return read.future;
      }
      return snapshots[arguments.single] ?? {};
    }
    final result = Completer<Map<String, dynamic>>();
    writes.add((id: arguments[0], value: arguments[1], result: result));
    return result.future;
  }

  @override
  Future<void> close() async {
    await updates.close();
    await super.close();
  }
}

class _SidebarApi implements SystemRustLibApi {
  @override
  Future<double?> crateApiSidebarUptime() async => 3600;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
