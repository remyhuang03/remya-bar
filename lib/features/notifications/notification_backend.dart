import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../src/rust/system_bridge/api.dart' as api;

const _icons = MethodChannel('top.remya.bar/icons');

/// Mirrors the process-wide Rust notification server for one output and
/// applies the Settings Do not disturb and popup duration preferences.
class NotificationBackend extends ChangeNotifier {
  NotificationBackend({SettingsClient? settings})
    : _settings = settings ?? SettingsClient();

  final SettingsClient _settings;
  StreamSubscription<api.NotificationCenter>? _subscription;
  StreamSubscription<SettingsChange>? _changes;
  Timer? _retry;
  bool _disposed = false;
  api.NotificationCenter? center;

  /// Saved Settings preferences; null until Settings answers.
  NotificationPreferences? preferences;

  /// The manual Do Not Disturb switch; null until Settings answers.
  bool? get doNotDisturb => preferences?.doNotDisturb;

  /// Why Do Not Disturb is in effect: null, manual, schedule or fullscreen.
  String? get quietReason => switch (center?.quietReason) {
    null || '' => null,
    final reason => reason,
  };
  String? _output;
  final _iconBytes = <String, Uint8List?>{};
  final _iconPaths = <String, String?>{};

  List<api.NotificationSnapshot> get history => [
    ...?center?.notifications.where((item) => !item.transient),
  ];
  List<api.NotificationSnapshot> get popups => [
    ...?center?.notifications.where((item) => item.popup),
  ];
  String? get error =>
      center == null ? 'Notification service starting' : center!.error;

  void start() {
    if (_disposed || _subscription != null) return;
    _changes = _settings.changes.listen((change) {
      if (notificationSettingIds.contains(change.topic)) {
        unawaited(_readPreferences());
      }
    }, onError: (Object error) => debugPrint('Notification settings: $error'));
    unawaited(_readPreferences());
    _subscribe();
  }

  void _subscribe() {
    if (_disposed) return;
    _subscription = api.subscribeNotifications().listen(
      (next) {
        center = next;
        notifyListeners();
        unawaited(_resolveIcons(next.notifications));
      },
      onError: (Object error) => debugPrint('Notifications: $error'),
      onDone: () {
        if (_disposed) return;
        _retry = Timer(const Duration(seconds: 1), _subscribe);
      },
    );
  }

  // Errors keep the last valid preferences, like the theme.
  Future<void> _readPreferences() async {
    try {
      final next = await _settings.readNotificationPreferences();
      if (_disposed) return;
      preferences = next;
      notifyListeners();
      await _configure(next);
    } catch (error) {
      if (!_disposed) debugPrint('Notification preferences: $error');
    }
  }

  Future<void> _configure(NotificationPreferences preferences) {
    int minutes(String time) {
      final [hours, minutes] = time.split(':').map(int.parse).toList();
      return hours * 60 + minutes;
    }

    return api.notificationsConfigure(
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

  Future<void> setDoNotDisturb(bool enabled) async {
    await _settings.setNotificationPreference(
      notificationDndSettingId,
      enabled,
    );
    await _readPreferences();
  }

  /// Reports this output's full screen state for automatic Do Not Disturb.
  Future<void> setFullscreen(String output, bool fullscreen) {
    _output = output;
    return api.notificationsFullscreen(output: output, fullscreen: fullscreen);
  }

  Future<void> dismiss(int? id) => api.notificationDismiss(id: id);
  Future<void> invoke(int id, String action) =>
      api.notificationInvoke(id: id, action: action);
  Future<bool> claimPopups(String output) =>
      api.notificationsClaimPopups(output: output);
  Future<void> hover(bool hovered) => api.notificationsHover(hovered: hovered);

  /// Resolves app icons and image paths to PNG bytes or files the popup
  /// views can read.
  Future<void> _resolveIcons(List<api.NotificationSnapshot> items) async {
    final names = <String>{};
    final entries = <String>{};
    for (final item in items) {
      for (final name in [item.appIcon, item.imagePath]) {
        final resolved = _iconName(name);
        if (resolved != null && !_iconBytes.containsKey(resolved)) {
          names.add(resolved);
        }
      }
      if (item.appIcon.isEmpty &&
          item.desktopEntry.isNotEmpty &&
          !_iconPaths.containsKey(item.desktopEntry)) {
        entries.add(item.desktopEntry);
      }
    }
    if (names.isEmpty && entries.isEmpty) return;
    for (final name in names) {
      _iconBytes[name] = null;
    }
    for (final entry in entries) {
      _iconPaths[entry] = null;
    }
    try {
      final (bytes, paths) = await (
        names.isEmpty
            ? Future.value(const <String, Uint8List>{})
            : _icons.invokeMapMethod<String, Uint8List>('lookupTray', [
                for (final name in names) [name, ''],
              ]),
        entries.isEmpty
            ? Future.value(const <String, String>{})
            : _icons.invokeMapMethod<String, String>(
                'lookup',
                entries.toList(),
              ),
      ).wait;
      if (_disposed) return;
      for (final name in names) {
        _iconBytes[name] = bytes?['\n$name'];
      }
      for (final entry in entries) {
        _iconPaths[entry] = paths?[entry];
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Notification icons: $error');
    }
  }

  /// Popup view data; images travel as PNG bytes or raw ARGB.
  Map<String, Object?> toData(api.NotificationSnapshot item) {
    final icon = _iconName(item.appIcon);
    final image = _iconName(item.imagePath);
    final iconIsFile = icon != null && icon.startsWith('/');
    return {
      'id': item.id,
      'appName': item.appName,
      'group': item.desktopEntry.isNotEmpty ? item.desktopEntry : item.appName,
      'summary': item.summary,
      'body': [
        for (final run in item.body)
          {
            'text': run.text,
            'bold': run.bold,
            'italic': run.italic,
            'underline': run.underline,
            'href': run.href,
          },
      ],
      'actions': [
        for (final action in item.actions) [action.key, action.label],
      ],
      'default': item.defaultAction,
      'urgency': item.urgency,
      'received': item.receivedUnixMs,
      'progress': item.progress,
      'icon': iconIsFile ? null : _iconBytes[icon],
      'iconPath': item.appIcon.isEmpty ? _iconPaths[item.desktopEntry] : null,
      if (item.imageArgb.isNotEmpty) ...{
        'imageArgb': item.imageArgb,
        'imageWidth': item.imageWidth,
        'imageHeight': item.imageHeight,
      } else
        'image': image != null
            ? _iconBytes[image]
            : iconIsFile
            ? _iconBytes[icon]
            : null,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    if (_output case final output?) {
      unawaited(api.notificationsFullscreen(output: output, fullscreen: false));
    }
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_changes?.cancel());
    unawaited(_settings.close());
    super.dispose();
  }
}

/// Icon names stay names; paths and file URIs become absolute paths.
String? _iconName(String value) {
  if (value.isEmpty) return null;
  if (value.startsWith('file://')) {
    try {
      return Uri.parse(value).toFilePath();
    } on FormatException {
      return null;
    }
  }
  return value.startsWith('/') || !value.contains('/') ? value : null;
}

/// Opens a notification body link; only web and mail links are accepted.
Future<void> openNotificationLink(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
    throw const FormatException('Unsupported notification link');
  }
  await Process.start('xdg-open', [
    uri.toString(),
  ], mode: ProcessStartMode.detached);
}
