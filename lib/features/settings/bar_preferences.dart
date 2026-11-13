import 'dart:convert';

import 'package:remya_client/remya_client.dart';

import 'bar_preference_models.dart';

export 'bar_preference_models.dart';

const barClockSecondsSettingId = 'remya-bar.clock-seconds';
const barKeyboardPreviewSettingId = 'remya-bar.keyboard-preview';
const barFoldedAppsSettingId = 'remya-bar.folded-apps';
const barSidebarLayoutSettingId = 'remya-bar.sidebar-layout';
const barNotificationsSettingId = 'remya-bar.notifications';
const aiRingSettingId = 'remya-bar.ai-ring';
const sidebarTileIds = [
  'internet',
  'bluetooth',
  'audio',
  'night-light',
  'dnd',
  'power',
  'caffeine',
  'record',
  'screenshot',
  'picker',
  'dark',
  'dnd-quick',
  'airplane',
  'keyboard',
  'clipboard',
  'mic-mute',
];

/// Bar owns validation and presentation; Core owns persistence and revisions.
class BarPreferences {
  BarPreferences({SettingsClient? client})
    : _store = AppPreferences('remya-bar', client: client);

  final AppPreferences _store;
  final _last = <String, Object>{};
  final _revisions = <String, String>{};

  Object? lastValid(String key) => _last[key];
  String revision(String key) =>
      _revisions[key] ?? (throw StateError('Read $key before replacing it'));

  Future<Object> read(String key) async => _accept(key, await _store.get(key));
  Future<Object> set(String key, Object value) async {
    validate(key, value);
    return _accept(key, await _store.set(key, value));
  }

  Future<Object> replace(String key, Object value, String revision) async {
    validate(key, value);
    return _accept(key, await _store.replace(key, value, revision));
  }

  Object _accept(String key, Map<String, dynamic> reply) {
    final value = reply['value'];
    validate(key, value);
    final revision = reply['revision'];
    if (revision is! String ||
        revision.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(revision)) {
      throw const FormatException('Invalid app preference revision');
    }
    // Freeze collections so callers cannot corrupt the last validated value.
    final frozen = _freeze(value!);
    _last[key] = frozen;
    _revisions[key] = revision;
    return frozen;
  }

  Future<BarLayout> readLayout() async =>
      BarLayout.fromJson(await read('layout'));
  Future<bool> readClockSeconds() async => await read('clock-seconds') as bool;
  Future<bool> readKeyboardPreview() async =>
      await read('keyboard-preview') as bool;
  Future<List<String>> readSidebarLayout() async =>
      List<String>.from(await read('sidebar-layout') as List);
  Future<Set<String>> readFoldedApps() async =>
      Set<String>.from(await read('folded-apps') as List);

  Future<Set<String>> setAppFolded(String id, bool folded) async {
    if (!_text(id)) throw const FormatException('Invalid tray app id');
    final current = await readFoldedApps();
    current.remove(id);
    if (folded) current.add(id);
    return Set<String>.from(
      await replace('folded-apps', current.toList(), revision('folded-apps'))
          as List,
    );
  }

  Future<BarOsdPreferences> readOsd() async {
    final value = await read('osd') as Map;
    return BarOsdPreferences(
      volumeStep: value['volume-step'] as int,
      volumeMax: value['volume-max'] as int,
      brightnessStep: value['brightness-step'] as int,
      gammaMin: value['gamma-min'] as int,
    );
  }

  Future<NotificationPreferences> readNotifications() async {
    final values = await Future.wait([
      read('notifications'),
      read('quiet-schedule'),
      read('priority-notifications'),
    ]);
    final [notifications as Map, quiet as Map, priority as Map] = values;
    return NotificationPreferences(
      doNotDisturb: notifications['do-not-disturb'] as bool,
      popupDuration: notifications['popup-duration'] as int,
      sounds: notifications['sounds'] as bool,
      schedule: quiet['enabled'] as bool,
      scheduleStart: quiet['start'] as String,
      scheduleEnd: quiet['end'] as String,
      scheduleRepeat: quiet['repeat'] as String,
      fullscreen: quiet['fullscreen'] as bool,
      priorityCalls: priority['calls'] as bool,
      priorityApps: [
        for (final Map app in priority['apps'] as List)
          (id: app['id'] as String, name: app['name'] as String),
      ],
    );
  }

  Future<bool> readDoNotDisturb() async =>
      (await read('notifications') as Map)['do-not-disturb'] as bool;
  Future<Map<String, dynamic>> setDoNotDisturb(bool enabled) async {
    final current = await read('notifications') as Map;
    final result = await replace('notifications', {
      ...current,
      'do-not-disturb': enabled,
    }, revision('notifications')) as Map;
    return {'value': result['do-not-disturb']};
  }

  Future<Map<String, dynamic>> readAiRing() async {
    final value = await read('ai-ring') as Map;
    return {
      'pinned': value['pinned'],
      'lowPercent': value['low-percent'],
      'showUsed': value['show-used'],
      'ringOrder': value['ring-order'],
    };
  }

  Future<void> close() => _store.close();

  /// Mirrors registration constraints and adds cross-field layout checks.
  static void validate(String key, Object? value) {
    bool valid;
    switch (key) {
      case 'clock-seconds' || 'keyboard-preview':
        valid = value is bool;
      case 'folded-apps':
        valid = _strings(value, _text);
      case 'sidebar-layout':
        valid = _strings(value, sidebarTileIds.contains);
      case 'layout':
        valid = _object(
          value,
          {
            'groups',
            'workspace-count',
            'resources',
            'window-app-name',
            'media-marquee',
          },
          optional: {'center'},
        );
        if (valid) {
          final map = value as Map;
          final groups = map['groups'];
          final seen = <String>{};
          valid =
              groups is List &&
              groups.isNotEmpty &&
              groups.every(
                (group) => _strings(
                  group,
                  (id) => barPillIds.contains(id) && seen.add(id),
                  nonEmpty: true,
                ),
              ) &&
              seen.contains('sidebar') &&
              _range(map['workspace-count'], 1, 10) &&
              _strings(
                map['resources'],
                barResourceIds.contains,
                nonEmpty: true,
              ) &&
              map['window-app-name'] is bool &&
              map['media-marquee'] is bool &&
              (!map.containsKey('center') ||
                  _range(map['center'], 0, groups.length - 1));
        }
      case 'osd':
        valid =
            _object(value, {
              'volume-step',
              'volume-max',
              'brightness-step',
              'gamma-min',
            }) &&
            _range((value as Map)['volume-step'], 1, 25) &&
            _range(value['volume-max'], 100, 150) &&
            _range(value['brightness-step'], 1, 25) &&
            _range(value['gamma-min'], 10, 90);
      case 'notifications':
        valid =
            _object(value, {'do-not-disturb', 'popup-duration', 'sounds'}) &&
            (value as Map)['do-not-disturb'] is bool &&
            value['sounds'] is bool &&
            _range(value['popup-duration'], 1, 60);
      case 'quiet-schedule':
        valid =
            _object(value, {
              'enabled',
              'start',
              'end',
              'repeat',
              'fullscreen',
            }) &&
            (value as Map)['enabled'] is bool &&
            value['fullscreen'] is bool &&
            _time(value['start']) &&
            _time(value['end']) &&
            quietRepeats.contains(value['repeat']);
      case 'priority-notifications':
        valid =
            _object(value, {'calls', 'apps'}) &&
            (value as Map)['calls'] is bool &&
            value['apps'] is List &&
            (value['apps'] as List).every(
              (app) =>
                  _object(app, {'id', 'name'}) &&
                  _text((app as Map)['id']) &&
                  _text(app['name']),
            );
        if (valid) {
          final ids = [for (final Map app in value['apps']) app['id']];
          valid = ids.toSet().length == ids.length;
        }
      case 'ai-ring':
        valid =
            _object(value, {
              'pinned',
              'low-percent',
              'show-used',
              'ring-order',
            }) &&
            _strings((value as Map)['pinned'], _text) &&
            (value['pinned'] as List).length <= 3 &&
            _range(value['low-percent'], 1, 100) &&
            value['show-used'] is bool &&
            const {'5h-outer', '5h-inner'}.contains(value['ring-order']);
      default:
        throw FormatException('Unknown Bar preference: $key');
    }
    if (!valid) throw FormatException('Invalid Bar preference: $key');
  }
}

bool _object(
  Object? value,
  Set<String> required, {
  Set<String> optional = const {},
}) =>
    value is Map &&
    required.every(value.containsKey) &&
    value.keys.every((key) => required.contains(key) || optional.contains(key));
bool _range(Object? value, int min, int max) =>
    value is int && value >= min && value <= max;
bool _text(Object? value) =>
    value is String &&
    value.trim().isNotEmpty &&
    utf8.encode(value).length <= 256 &&
    !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value);
bool _time(Object? value) =>
    value is String &&
    value.length == 5 &&
    RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value);
bool _strings(
  Object? value,
  bool Function(String) valid, {
  bool nonEmpty = false,
}) =>
    value is List &&
    (!nonEmpty || value.isNotEmpty) &&
    value.every((id) => id is String && valid(id)) &&
    value.toSet().length == value.length;
Object _freeze(Object value) => switch (value) {
  final Map map => Map<String, Object>.unmodifiable({
    for (final entry in map.entries)
      entry.key as String: _freeze(entry.value as Object),
  }),
  final List list => List<Object>.unmodifiable(
    list.map((item) => _freeze(item as Object)),
  ),
  _ => value,
};
