import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import 'bar_preferences.dart';

/// Keys edited in the Bar settings window, as registered in remya-bar.json.
const barSettingsKeys = [
  'layout',
  'clock-seconds',
  'keyboard-preview',
  'folded-apps',
  'osd',
  'notifications',
  'quiet-schedule',
  'priority-notifications',
  'ai-ring',
];

/// Short user-facing text for Core, validation and transport errors.
String barSettingsError(Object error) => switch (error) {
  StateError(:final message) => message,
  FormatException(:final message) => message,
  TimeoutException() => 'Remya Core did not respond. Try again.',
  _ =>
    '$error'
        .replaceFirst('top.remya.Core1.', '')
        .replaceFirst('org.freedesktop.DBus.Error.', ''),
};

/// Last valid Bar preferences for the settings window. Every edit replaces the
/// displayed value with its revision, so a change from another view surfaces
/// Core's conflict message instead of being overwritten.
class BarSettingsController extends ChangeNotifier {
  BarSettingsController({SettingsClient? client})
    : client = client ?? SettingsClient(),
      _ownsClient = client == null {
    preferences = BarPreferences(client: this.client);
  }

  final SettingsClient client;
  final bool _ownsClient;
  late final BarPreferences preferences;

  final values = <String, Object>{};

  /// Read errors clear on the next successful read; write errors (including
  /// conflicts) stay until the user reloads the key or writes it again.
  final readErrors = <String, String>{};
  final writeErrors = <String, String>{};
  final _busy = <String>{};

  /// Tracked AI providers from Core's `ai.providers`, or null before a read.
  List<Map<String, dynamic>>? aiProviders;
  String? aiError;

  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _disposed = false;

  bool busy(String key) => _busy.contains(key);
  String? error(String key) => writeErrors[key] ?? readErrors[key];

  /// Subscribes before the first reads so concurrent writes are not missed.
  Future<void> start() async {
    _subscriptions
      ..add(
        client.changes.listen((change) {
          if (change.topic == aiProvidersSettingId) {
            unawaited(loadAi());
          } else if (change.topic.startsWith('remya-bar.')) {
            final key = change.topic.substring('remya-bar.'.length);
            if (barSettingsKeys.contains(key)) unawaited(load(key));
          }
        }, onError: (Object _) {}),
      )
      ..add(
        client.serviceAvailableChanges.listen((available) {
          if (available) unawaited(reload());
        }, onError: (Object _) {}),
      );
    await reload();
  }

  Future<void> reload() async {
    writeErrors.clear();
    await Future.wait([for (final key in barSettingsKeys) load(key), loadAi()]);
  }

  Future<void> load(String key) async {
    try {
      values[key] = await preferences.read(key);
      readErrors.remove(key);
    } catch (error) {
      readErrors[key] = barSettingsError(error);
    }
    _notify();
  }

  /// Rereads [key] and dismisses its write error, e.g. after a conflict.
  Future<void> reloadKey(String key) {
    writeErrors.remove(key);
    return load(key);
  }

  Future<void> loadAi() async {
    try {
      final value = await client.readAi();
      aiProviders = [
        for (final row in (value['providers'] as List?) ?? const [])
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      aiError = null;
    } catch (error) {
      aiError = barSettingsError(error);
    }
    _notify();
  }

  /// Replaces [key] using the revision of the value currently displayed.
  Future<void> write(String key, Object value) async {
    if (!values.containsKey(key) || !_busy.add(key)) return;
    _notify();
    try {
      values[key] = await preferences.replace(
        key,
        value,
        preferences.revision(key),
      );
      writeErrors.remove(key);
      readErrors.remove(key);
    } catch (error) {
      writeErrors[key] = barSettingsError(error);
    } finally {
      _busy.remove(key);
      _notify();
    }
  }

  /// Writes one field of an object preference.
  Future<void> update(String key, String field, Object value) =>
      write(key, {...values[key]! as Map, field: value});

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(preferences.close());
    if (_ownsClient) unawaited(client.close());
    super.dispose();
  }
}
