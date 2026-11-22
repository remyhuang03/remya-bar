import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/notifications/notification_settings.dart';
import 'package:remya_bar/features/settings/bar_preference_models.dart';
import 'package:remya_bar/features/settings/bar_settings_controller.dart';
import 'package:remya_client/remya_client.dart';

class _Client extends SettingsClient {
  final _changes = StreamController<SettingsChange>.broadcast(sync: true);
  final values = <String, Object>{
    'position': 'top',
    'notifications': {
      'do-not-disturb': false,
      'popup-duration': 5,
      'sounds': true,
    },
    'quiet-schedule': {
      'enabled': false,
      'start': '22:00',
      'end': '07:00',
      'repeat': 'every-day',
      'fullscreen': false,
    },
    'priority-notifications': {'calls': true, 'apps': []},
  };
  final versions = <String, int>{};
  final reads = <String>[];
  Completer<void>? blockRead;
  Completer<void>? blockWrite;

  String revision(String key) =>
      (versions[key] ?? 1).toString().padLeft(64, '0');

  void external(String key, Object value) {
    values[key] = value;
    versions.update(key, (value) => value + 1, ifAbsent: () => 2);
    _changes.add((topic: 'remya-bar.$key', value: const {}));
  }

  @override
  Stream<SettingsChange> get changes => _changes.stream;

  @override
  Stream<bool> get serviceAvailableChanges => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    final key = arguments.first.substring('remya-bar.'.length);
    if (method == 'Get') {
      reads.add(key);
      final snapshot = {'value': values[key], 'revision': revision(key)};
      final gate = blockRead;
      blockRead = null;
      await gate?.future;
      return snapshot;
    }

    expect(method, 'Replace');
    final gate = blockWrite;
    blockWrite = null;
    await gate?.future;
    if (arguments[2] != revision(key)) throw StateError('Revision conflict');
    external(key, jsonDecode(arguments[1]) as Object);
    return {'value': values[key], 'revision': revision(key)};
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await super.close();
  }
}

void main() {
  test(
    'a delayed read cannot revert a confirmed write or its revision',
    () async {
      final client = _Client();
      addTearDown(client.close);
      final controller = BarSettingsController(client: client);
      addTearDown(controller.dispose);
      await controller.load('position');

      final gate = client.blockRead = Completer<void>();
      final stale = controller.load('position');
      await controller.write('position', 'bottom');
      gate.complete();
      await stale;
      expect(controller.values['position'], 'bottom');
      expect(
        controller.preferences.revision('position'),
        client.revision('position'),
      );

      client.external('position', 'top');
      await controller.write('position', 'bottom');
      expect(controller.error('position'), 'Revision conflict');
      expect(controller.values['position'], 'bottom');
      await controller.reloadKey('position');
      expect(controller.error('position'), isNull);
      expect(controller.values['position'], 'top');
    },
  );

  test('reads requested during a write begin after confirmation', () async {
    final client = _Client();
    addTearDown(client.close);
    final controller = BarSettingsController(client: client);
    addTearDown(controller.dispose);
    await controller.load('position');

    final gate = client.blockWrite = Completer<void>();
    final write = controller.write('position', 'bottom');
    final read = controller.load('position');
    expect(client.reads, ['position']);
    gate.complete();
    await Future.wait([write, read]);
    expect(client.reads, ['position', 'position']);
    expect(controller.values['position'], 'bottom');
  });

  test(
    'notification changes coalesce during reads and serialize configuration',
    () async {
      final client = _Client();
      addTearDown(client.close);
      final applied = <NotificationPreferences>[];
      final toastSides = <bool>[];
      final configure = Completer<void>();
      final settings = NotificationSettings(
        client: client,
        onToastSideChanged: toastSides.add,
        configure: (next) async {
          applied.add(next);
          await configure.future;
        },
      );
      addTearDown(settings.close);

      final read = client.blockRead = Completer<void>();
      settings.start();
      client.external('notifications', {
        'do-not-disturb': true,
        'popup-duration': 6,
        'sounds': false,
      });
      expect(client.reads.where((key) => key == 'notifications'), hasLength(1));
      read.complete();
      await pumpEventQueue();
      expect(applied.map((value) => value.popupDuration), [6]);

      client.external('notifications', {
        'do-not-disturb': false,
        'popup-duration': 600,
        'sounds': true,
        'clear-critical': true,
        'toast-side': 'right',
      });
      await pumpEventQueue();
      expect(applied.map((value) => value.popupDuration), [6]);
      configure.complete();
      await pumpEventQueue();
      expect(applied.map((value) => value.popupDuration), [6, 600]);
      expect(applied.map((value) => value.doNotDisturb), [true, false]);
      expect(applied.map((value) => value.clearCritical), [false, true]);
      expect(toastSides, [false, true]);
    },
  );

  test('closing notification settings discards an outstanding read', () async {
    final client = _Client();
    addTearDown(client.close);
    var configured = 0;
    final settings = NotificationSettings(
      client: client,
      configure: (_) async => configured++,
    );
    final read = client.blockRead = Completer<void>();
    settings.start();
    await settings.close();
    read.complete();
    await pumpEventQueue();
    expect(configured, 0);
  });
}
