import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import 'bar_preferences.dart';

/// Keys edited in the Bar settings window, as registered in remya-bar.json.
const barSettingsKeys = [
  'layout',
  'position',
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
  TimeoutException() => "Remy'a Core did not respond. Try again.",
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

  Map<String, Object> get values => preferences.values;

  /// Read errors clear on the next successful read; write errors (including
  /// conflicts) stay until the user reloads the key or writes it again.
  final readErrors = <String, String>{};
  final writeErrors = <String, String>{};
  final _writes = <String, Completer<void>>{};
  final _readGeneration = <String, int>{};

  /// Tracked AI providers from Core's `ai.providers`, or null before a read.
  List<Map<String, dynamic>>? aiProviders;
  String? aiError;
  int _aiGeneration = 0;

  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _disposed = false;

  bool busy(String key) => _writes.containsKey(key);
  String? error(String key) => writeErrors[key] ?? readErrors[key];

  /// Subscribes before the first reads so concurrent writes are not missed.
  Future<void> start() async {
    if (_disposed || _subscriptions.isNotEmpty) return;
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
    while (busy(key)) {
      await _writes[key]!.future;
    }
    if (_disposed) return;
    final generation = _advanceRead(key);
    bool isCurrent() => !_disposed && _readGeneration[key] == generation;
    try {
      await preferences.read(key, isCurrent: isCurrent);
      if (!isCurrent()) return;
      readErrors.remove(key);
    } catch (error) {
      if (!isCurrent()) return;
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
    if (_disposed) return;
    final generation = ++_aiGeneration;
    try {
      final value = await client.readAi();
      if (_disposed || generation != _aiGeneration) return;
      aiProviders = [
        for (final row in (value['providers'] as List?) ?? const [])
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      aiError = null;
    } catch (error) {
      if (_disposed || generation != _aiGeneration) return;
      aiError = barSettingsError(error);
    }
    _notify();
  }

  /// Replaces [key] using the revision of the value currently displayed.
  Future<void> write(String key, Object value) async {
    if (_disposed || !values.containsKey(key) || busy(key)) return;
    final write = _writes[key] = Completer<void>();
    final revision = preferences.revision(key);
    _advanceRead(key);
    _notify();
    try {
      await preferences.replace(
        key,
        value,
        revision,
        isCurrent: () => !_disposed,
      );
      if (_disposed) return;
      writeErrors.remove(key);
      readErrors.remove(key);
    } catch (error) {
      if (!_disposed) writeErrors[key] = barSettingsError(error);
    } finally {
      _writes.remove(key);
      write.complete();
      _notify();
    }
  }

  /// Writes one field of an object preference.
  Future<void> update(String key, String field, Object value) =>
      write(key, {...values[key]! as Map, field: value});

  int _advanceRead(String key) =>
      _readGeneration.update(key, (value) => value + 1, ifAbsent: () => 1);

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
