import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_bar/features/settings/bar_theme_controller.dart';

class _Client extends SettingsClient {
  _Client(this.values);
  final Map<String, dynamic> values;
  final writes = <List<String>>[];
  int version = 1;
  bool conflict = false;

  String get revision => version.toRadixString(16).padLeft(64, '0');

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    final key = arguments.first.substring('remya-bar.'.length);
    if (method != 'Get') {
      writes.add([method, ...arguments]);
      if (method == 'Replace' && (conflict || arguments[2] != revision)) {
        throw StateError('Changed in another view. Reopen the editor.');
      }
      values[key] = jsonDecode(arguments[1]);
      version++;
    }
    return {'value': values[key], 'revision': revision};
  }
}

Map<String, dynamic> _defaults() => {
  for (final MapEntry(:key, :value)
      in (jsonDecode(
                File('linux/packaging/remya-bar.json').readAsStringSync(),
              )['settings']
              as Map<String, dynamic>)
          .entries)
    key: value['default'],
};

void main() {
  test('debug theme resolves Bar override, Core shared theme, then XDG', () {
    final root = Directory.systemTemp.createTempSync('bar-theme-resolution-');
    addTearDown(() => root.deleteSync(recursive: true));
    final bar = Directory('${root.path}/remya-bar')..createSync();
    final local = File('${bar.path}/config/config.local.toml');
    final core = File('${root.path}/remya-core/config/shared/theme.toml');
    expect(
      resolveBarTheme(isDebug: true, repositoryDirectory: bar).path,
      settingsConfigFile(isDebug: false).path,
    );
    core.parent.createSync(recursive: true);
    core.writeAsStringSync('core');
    expect(
      resolveBarTheme(isDebug: true, repositoryDirectory: bar).path,
      core.path,
    );
    local.parent.createSync(recursive: true);
    local.writeAsStringSync('bar');
    expect(
      resolveBarTheme(isDebug: true, repositoryDirectory: bar).path,
      local.path,
    );
    expect(
      resolveBarTheme(isDebug: false, repositoryDirectory: bar).path,
      settingsConfigFile(isDebug: false).path,
    );
  });

  test(
    'registration defaults satisfy all Bar validations and typed readers',
    () async {
      final values = _defaults();
      final client = _Client(values);
      addTearDown(client.close);
      final prefs = BarPreferences(client: client);
      for (final key in values.keys) {
        expect(await prefs.read(key), values[key], reason: key);
      }
      expect(await prefs.readLayout(), BarLayout.defaults);
      expect(await prefs.readClockSeconds(), isTrue);
      expect(await prefs.readKeyboardPreview(), isTrue);
      expect(await prefs.readOsd(), const BarOsdPreferences());
      expect((await prefs.readNotifications()).popupDuration, 5);
      expect((await prefs.readAiRing())['lowPercent'], 20);
    },
  );

  test(
    'cross-field-invalid layouts retain the last value and revision',
    () async {
      final client = _Client(_defaults());
      addTearDown(client.close);
      final prefs = BarPreferences(client: client);
      await prefs.readLayout();
      final previous = prefs.lastValid('layout');
      final revision = prefs.revision('layout');
      for (final groups in [
        [
          ['sidebar'],
          ['sidebar'],
        ],
        [
          ['sidebar'],
        ],
      ]) {
        final invalid = {
          ...BarLayout.defaults.toJson(),
          'groups': groups,
          'center': 1,
        };
        client.values['layout'] = invalid;
        await expectLater(prefs.readLayout(), throwsFormatException);
        await expectLater(prefs.set('layout', invalid), throwsFormatException);
        expect(prefs.lastValid('layout'), same(previous));
        expect(prefs.revision('layout'), revision);
        expect(client.writes, isEmpty);
      }
    },
  );

  test('folded apps replace the fresh value with its revision and retain on conflict', () async {
    final client = _Client(_defaults());
    addTearDown(client.close);
    final prefs = BarPreferences(client: client);
    client.values['folded-apps'] = ['other'];
    expect(await prefs.setAppFolded('tray', true), {'other', 'tray'});
    expect(client.writes.single.first, 'Replace');
    expect(client.writes.single[3], '1'.padLeft(64, '0'));
    client.conflict = true;
    await expectLater(prefs.setAppFolded('tray', false), throwsStateError);
    expect(prefs.lastValid('folded-apps'), ['other', 'tray']);
  });

  test(
    'sidebar revision conflicts surface the Core error without replacing state',
    () async {
      final client = _Client(_defaults());
      addTearDown(client.close);
      final prefs = BarPreferences(client: client);
      final previous = await prefs.readSidebarLayout();
      final revision = prefs.revision('sidebar-layout');
      client.version++;
      await expectLater(
        prefs.replace('sidebar-layout', ['audio'], revision),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Changed in another view. Reopen the editor.',
          ),
        ),
      );
      expect(prefs.lastValid('sidebar-layout'), previous);
    },
  );

  test(
    'Bar-only constraints reject unsafe ids and duplicate priority app ids',
    () {
      for (final ids in [
        [''],
        ['a\n'],
        ['a', 'a'],
        ['é' * 129],
      ]) {
        expect(
          () => BarPreferences.validate('folded-apps', ids),
          throwsFormatException,
        );
      }
      expect(
        () => BarPreferences.validate('priority-notifications', {
          'calls': true,
          'apps': [
            {'id': 'app', 'name': 'A'},
            {'id': 'app', 'name': 'B'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => BarPreferences.validate('sidebar-layout', ['vpn']),
        throwsFormatException,
      );
    },
  );
}
