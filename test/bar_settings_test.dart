import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/settings/bar_pill_layout.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_bar/features/settings/bar_settings_controller.dart';
import 'package:remya_bar/features/settings/bar_settings_entry.dart';
import 'package:remya_bar/features/settings/remya_settings_installed.dart';
import 'package:remya_client/remya_client.dart';

/// Core stand-in with registration defaults, revisions and Changed signals.
class _Client extends SettingsClient {
  _Client()
    : values = {
        for (final MapEntry(:key, :value)
            in (jsonDecode(
                      File('linux/packaging/remya-bar.json').readAsStringSync(),
                    )['settings']
                    as Map<String, dynamic>)
                .entries)
          key: value['default'],
      };

  final Map<String, dynamic> values;
  final signals = StreamController<SettingsChange>.broadcast();
  final versions = <String, int>{};
  Object? failure;

  /// Core revisions are per setting.
  String revision(String key) =>
      (versions[key] ?? 1).toRadixString(16).padLeft(64, '0');
  void bump(String key) => versions[key] = (versions[key] ?? 1) + 1;

  /// Simulates a write from another view.
  void external(String key, Object value) {
    values[key] = value;
    bump(key);
    signals.add((topic: 'remya-bar.$key', value: const {}));
  }

  @override
  Stream<SettingsChange> get changes => signals.stream;

  @override
  Stream<bool> get serviceAvailableChanges => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (failure case final error?) throw error;
    if (arguments.first == aiProvidersSettingId) {
      return {
        'value': {
          'providers': [
            {
              'id': 'codex',
              'name': 'Codex',
              'kind': 'codexbar',
              'enabled': true,
            },
          ],
        },
      };
    }
    final key = arguments.first.substring('remya-bar.'.length);
    if (method == 'Replace') {
      if (arguments[2] != revision(key)) {
        throw StateError('Changed in another view. Reopen the editor.');
      }
      values[key] = jsonDecode(arguments[1]);
      bump(key);
    }
    return {'value': values[key], 'revision': revision(key)};
  }
}

void main() {
  const layout = BarLayout(
    groups: [
      ['window', 'resources'],
      ['clock'],
      ['sidebar'],
    ],
    center: 1,
  );

  test('pill moves keep the centered group and drop empty groups', () {
    expect(layout.movePill('window', 0, 1).groups.first, [
      'resources',
      'window',
    ]);
    final merged = layout.movePill('clock', 2, 0);
    expect(merged.groups, [
      ['window', 'resources'],
      ['clock', 'sidebar'],
    ]);
    expect(merged.center, isNull);
    final added = layout.movePill('battery', 3);
    expect(added.groups.last, ['battery']);
    expect(added.center, 1);
    final hidden = layout.hidePill('window').hidePill('resources');
    expect(hidden.groups, [
      ['clock'],
      ['sidebar'],
    ]);
    expect(hidden.center, 0);
    final moved = layout.moveGroup(1, 2);
    expect(moved.groups.last, ['clock']);
    expect(moved.center, 2);
    final removed = layout.removeGroup(0);
    expect(removed.hidden, contains('window'));
    expect(removed.center, 0);
    expect(BarLayout.defaults.hidden, ['media']);
    final enabled = layout.copyWith(mediaMarquee: true).movePill('media', 0);
    expect(BarLayout.fromJson(enabled.toJson()).mediaMarquee, isTrue);
    expect(
      () => BarPreferences.validate('layout', enabled.toJson()),
      returnsNormally,
    );
  });

  testWidgets('editor drags pills into new groups and edits groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BarLayout? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BarPillLayoutEditor(
              layout: layout,
              showSeconds: true,
              onChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Clock')),
    );
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveTo(
      tester.getCenter(find.text('Drop a pill here to add a group')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(changed!.groups.last, ['clock']);
    expect(changed!.center, isNull);

    await tester.tap(find.byTooltip('Center on bar').first);
    expect(changed!.center, 0);
    await tester.tap(find.byTooltip('Remove group').first);
    expect(changed!.groups, [
      ['clock'],
      ['sidebar'],
    ]);
    await tester.tap(find.text('Reset layout'));
    expect(changed!.groups, BarLayout.defaults.groups);
    expect(changed!.center, BarLayout.defaults.center);
  });

  test(
    'stale edits surface the conflict and keep the last valid value',
    () async {
      final client = _Client();
      final controller = BarSettingsController(client: client);
      addTearDown(controller.dispose);
      await controller.start();
      expect((controller.values['osd'] as Map)['volume-step'], 5);

      // Another view writes; this view still edits the value it displayed.
      client.values['osd'] = {
        ...client.values['osd'] as Map,
        'volume-max': 120,
      };
      client.bump('osd');
      await controller.update('osd', 'volume-step', 10);
      expect(
        controller.error('osd'),
        'Changed in another view. Reopen the editor.',
      );
      expect((controller.values['osd'] as Map)['volume-step'], 5);
      expect((client.values['osd'] as Map)['volume-step'], 5);

      // A Changed reread updates the value but keeps the conflict visible.
      client.signals.add((topic: 'remya-bar.osd', value: const {}));
      await pumpEventQueue();
      expect((controller.values['osd'] as Map)['volume-max'], 120);
      expect(controller.error('osd'), isNotNull);

      await controller.reloadKey('osd');
      expect(controller.error('osd'), isNull);
      await controller.update('osd', 'volume-step', 10);
      expect(controller.error('osd'), isNull);
      expect(client.values['osd'], {
        'volume-step': 10,
        'volume-max': 120,
        'brightness-step': 5,
        'gamma-min': 10,
      });

      // Core errors keep the last valid value and report the error.
      client.failure = StateError('Unavailable: Remya Core is not running');
      await controller.load('osd');
      expect(controller.error('osd'), 'Unavailable: Remya Core is not running');
      expect((controller.values['osd'] as Map)['volume-step'], 10);
    },
  );

  testWidgets('window follows later open requests and external changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    final controller = BarSettingsController(client: client);
    await tester.runAsync(controller.start);
    Future<void> open(String page, int request) async {
      await tester.pumpWidget(
        BarSettingsEntry(page: page, request: request, controller: controller),
      );
      await tester.pumpAndSettle();
    }

    await open('osd', 1);
    expect(find.text('Maximum volume'), findsOneWidget);
    await open('notifications', 2);
    expect(find.text('Popup duration'), findsOneWidget);
    // Schedule details stay hidden until the schedule is on.
    expect(find.text('Start time'), findsNothing);
    await tester.runAsync(() async {
      client.external('quiet-schedule', {
        ...client.values['quiet-schedule'] as Map,
        'enabled': true,
      });
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(find.text('Start time'), findsOneWidget);

    await tester.tap(find.text('AI quota rings'));
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
    await tester.tap(find.text('Show in bar'));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect((client.values['ai-ring'] as Map)['pinned'], ['codex']);
    expect(find.byTooltip('Hide from bar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('Settings installation follows absolute XDG data roots', () {
    final root = Directory.systemTemp.createTempSync('bar-settings-xdg-');
    addTearDown(() => root.deleteSync(recursive: true));
    final entry = File(
      '${root.path}/data/applications/top.remya.settings.desktop',
    )..createSync(recursive: true);
    bool installed(Map<String, String> env) =>
        remyaSettingsInstalled(environment: env);
    expect(installed({'XDG_DATA_HOME': '${root.path}/data'}), isTrue);
    expect(
      installed({
        'HOME': '/nonexistent',
        'XDG_DATA_DIRS': 'relative:${root.path}/data',
      }),
      isTrue,
    );
    expect(installed({'XDG_DATA_HOME': 'data', 'HOME': root.path}), isFalse);
    entry.deleteSync();
    expect(installed({'XDG_DATA_HOME': '${root.path}/data'}), isFalse);
  });
}
