import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../settings/bar_preferences.dart';
import '../system/system_backend.dart' show SystemBackend;

/// Applies Core preferences to the process-wide Rust notification server.
class NotificationSettings {
  NotificationSettings({
    SettingsClient? client,
    Future<void> Function(NotificationPreferences)? configure,
  }) : _client = client ?? SettingsClient(),
       _ownsClient = client == null,
       _configure = configure ?? _configureRust;

  final SettingsClient _client;
  final bool _ownsClient;
  final Future<void> Function(NotificationPreferences) _configure;
  late final _preferences = BarPreferences(client: _client);
  StreamSubscription<SettingsChange>? _changes;
  StreamSubscription<bool>? _availability;
  Future<void>? _reading;
  Timer? _retry;
  bool _dirty = false;
  bool _disposed = false;

  void start() {
    if (_disposed || _changes != null) return;
    _changes = _client.changes.listen((change) {
      if (notificationSettingIds.contains(change.topic)) _refresh();
    }, onError: (Object error) => debugPrint('Notification settings: $error'));
    _availability = _client.serviceAvailableChanges.listen((available) {
      if (available) _refresh();
    }, onError: (Object error) => debugPrint('Notification settings: $error'));
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    _retry?.cancel();
    _dirty = true;
    _reading ??= _readChanges().whenComplete(() {
      _reading = null;
      if (_dirty) _refresh();
    });
  }

  Future<void> _readChanges() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      try {
        final preferences = await _preferences.readNotifications();
        if (_disposed) return;
        if (!_dirty) await _configure(preferences);
      } catch (error) {
        if (_disposed) return;
        debugPrint('Notification preferences: $error');
        if (!_dirty) _retry = Timer(const Duration(seconds: 5), _refresh);
      }
    }
  }

  Future<void> close() async {
    _disposed = true;
    _retry?.cancel();
    await _changes?.cancel();
    await _availability?.cancel();
    if (_ownsClient) await _client.close();
  }

  static Future<void> _configureRust(
    NotificationPreferences preferences,
  ) async {
    int minutes(String time) {
      final [hours, minutes] = time.split(':').map(int.parse).toList();
      return hours * 60 + minutes;
    }

    await SystemBackend.initialize();
    await api.notificationsConfigure(
      preferences: api.NotificationPreferences(
        doNotDisturb: preferences.doNotDisturb,
        timeoutSeconds: preferences.popupDuration,
        sounds: preferences.sounds,
        schedule: preferences.schedule,
        scheduleStartMinutes: minutes(preferences.scheduleStart),
        scheduleEndMinutes: minutes(preferences.scheduleEnd),
        scheduleDays: Uint32List.fromList(switch (preferences.scheduleRepeat) {
          'weekdays' => [1, 2, 3, 4, 5],
          'weekends' => [6, 7],
          _ => [1, 2, 3, 4, 5, 6, 7],
        }),
        fullscreen: preferences.fullscreen,
        priorityCalls: preferences.priorityCalls,
        priorityApps: [
          for (final app in preferences.priorityApps)
            api.NotificationPriorityApp(id: app.id, name: app.name),
        ],
      ),
    );
  }
}
