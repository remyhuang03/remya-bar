import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_bar/features/settings/bar_theme_controller.dart';
import 'package:remya_bar/features/tasks/tasks_preferences.dart';

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
      expect(await prefs.readResources(), BarResourcePreferences.defaults);
      expect(await prefs.readBottom(), isFalse);
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

  test('Tasks clock preferences apply only to their account', () {
    expect(_defaults().containsKey('tasks'), false);
    expect(_defaults()[tasksClockPreferenceKey], tasksClockDefaults);
    final value = {
      ...tasksClockDefaults,
      'visible-lists': ['selected-list'],
      'visible-lists-account': 'account',
    };
    BarPreferences.validate(tasksClockPreferenceKey, value);
    final preferences = TasksPreferences.fromJson(value);
    expect(preferences.visibleListsFor('account'), ['selected-list']);
    expect(preferences.visibleListsFor('other'), isEmpty);
    expect(preferences.upcomingDays, 7);
    expect(preferences.workingOnLimit, 3);
    expect(preferences.workingOnEnabled, true);
    for (final invalid in [
      {'visible-lists-account': ''},
      {'upcoming-days': 5},
      {'working-on-limit': 0},
      {'working-on-limit': 4},
      {'automatic': true},
    ]) {
      expect(
        () => BarPreferences.validate(tasksClockPreferenceKey, {
          ...value,
          ...invalid,
        }),
        throwsFormatException,
      );
    }
  });

  test('Calendar validates week starts and isolates visibility by account', () {
    expect(_defaults()['calendar'], calendarDefaults);
    for (final start in ['system', 'monday', 'sunday']) {
      expect(
        () => BarPreferences.validate('calendar', {
          ...calendarDefaults,
          'week-start': start,
        }),
        returnsNormally,
      );
    }
    final preferences = {
      ...calendarDefaults,
      'calendar-account': 'subject',
      'hidden-calendars': ['original'],
      'shown-calendars': ['extra'],
    };
    BarPreferences.validate('calendar', preferences);
    expect(barCalendarVisible(preferences, 'subject', 'original', true), false);
    expect(barCalendarVisible(preferences, 'subject', 'extra', false), true);
    expect(barCalendarVisible(preferences, 'other', 'original', true), true);
    expect(barCalendarVisible(preferences, 'other', 'extra', false), false);
    for (final invalid in [
      {'week-start': 'tuesday'},
      {'calendar-account': ''},
      {
        'shown-calendars': ['original'],
      },
    ]) {
      expect(
        () => BarPreferences.validate('calendar', {...preferences, ...invalid}),
        throwsFormatException,
      );
    }
  });

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
    'weather location replaces by revision and retains valid coordinates',
    () async {
      const key = barWeatherLocationKey;
      const location = {
        'latitude': 25.0478,
        'longitude': 121.5319,
        'name': '臺北',
        'id': 1668341,
        'region': 'Taipei City',
        'country': 'Taiwan',
      };
      final client = _Client(_defaults());
      addTearDown(client.close);
      final prefs = BarPreferences(client: client);
      final (value: empty, revision: initial) = await prefs
          .readWeatherLocationPreference();
      expect(empty, isEmpty);
      expect(await prefs.replace(key, location, initial), location);
      final saved = prefs.lastValid(key);
      final revision = prefs.revision(key);
      expect(client.writes.single.first, 'Replace');
      expect(client.writes.single[3], initial);

      for (final invalid in [
        {'latitude': 0, 'longitude': 0},
        {...location, 'latitude': double.nan},
        {...location, 'longitude': double.infinity},
        {...location, 'longitude': -9223372036854775808},
        {...location, 'name': '  '},
        {...location, 'id': 0},
        {...location, 'region': null},
        {...location, 'country': 'a\n'},
        {...location, 'unknown': 'value'},
      ]) {
        client.values[key] = invalid;
        await expectLater(prefs.read(key), throwsFormatException);
        await expectLater(
          prefs.replace(key, invalid, revision),
          throwsFormatException,
        );
        expect(prefs.lastValid(key), same(saved));
        expect(prefs.revision(key), revision);
      }
      expect(client.writes, hasLength(1));
      client.conflict = true;
      await expectLater(prefs.replace(key, {}, revision), throwsStateError);
      expect(prefs.lastValid(key), same(saved));
      client.conflict = false;
      expect(await prefs.replace(key, {}, revision), isEmpty);
    },
  );

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
      for (final position in ['left', 'Top', true]) {
        expect(
          () => BarPreferences.validate('position', position),
          throwsFormatException,
        );
      }
      expect(
        () => BarPreferences.validate('resources', {
          'refresh-interval-ms': 500,
          'time-range-seconds': 600,
        }),
        returnsNormally,
      );
      for (final invalid in [
        {'refresh-interval-ms': 250, 'time-range-seconds': 60},
        {'refresh-interval-ms': 1000, 'time-range-seconds': 15},
        {'refresh-interval-ms': 1000},
      ]) {
        expect(
          () => BarPreferences.validate('resources', invalid),
          throwsFormatException,
        );
      }
      expect(
        () => BarPreferences.validate('weather', {
          ...weatherDefaults,
          'enabled': false,
        }),
        throwsFormatException,
      );
    },
  );
}
