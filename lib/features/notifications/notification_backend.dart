import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../../widgets/bar_icon_cache.dart';

/// Mirrors the process-wide Rust notification server for one output.
class NotificationBackend extends ChangeNotifier {
  NotificationBackend({SettingsClient? settings})
    : _settings = settings ?? SettingsClient(),
      _ownsSettings = settings == null;

  final SettingsClient _settings;
  final bool _ownsSettings;
  late final _preferences = BarPreferences(client: _settings);
  StreamSubscription<api.NotificationCenter>? _subscription;
  Timer? _retry;
  bool _disposed = false;
  api.NotificationCenter? center;

  /// The manual Do Not Disturb switch; null until Rust applies Core's values.
  bool? get doNotDisturb => center?.doNotDisturb;

  /// Why Do Not Disturb is in effect: null, manual, schedule or fullscreen.
  String? get quietReason => switch (center?.quietReason) {
    null || '' => null,
    final reason => reason,
  };
  String? _output;
  late final _iconBytes = BarIconCache<Uint8List>(
    lookup: _lookupIconBytes,
    onChanged: notifyListeners,
    size: (bytes) => bytes.lengthInBytes,
    refreshAfter: (key) =>
        key.startsWith('/') ? const Duration(seconds: 30) : null,
    retryOnIdle: true,
  );
  late final _iconPaths = BarIconCache<String>(
    lookup: lookupBarIconPaths,
    onChanged: notifyListeners,
    retryOnIdle: true,
  );

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
    _subscribe();
  }

  void _subscribe() {
    if (_disposed) return;
    _subscription = api.subscribeNotifications().listen(
      (next) {
        if (_disposed) return;
        center = next;
        notifyListeners();
        _resolveIcons(next.notifications);
      },
      onError: (Object error) => debugPrint('Notifications: $error'),
      onDone: () {
        if (_disposed) return;
        _retry = Timer(const Duration(seconds: 1), _subscribe);
      },
    );
  }

  Future<void> setDoNotDisturb(bool enabled) async {
    await _preferences.setDoNotDisturb(enabled);
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
  void _resolveIcons(List<api.NotificationSnapshot> items) {
    final names = <String>{};
    final entries = <String>{};
    for (final item in items.reversed) {
      for (final name in [item.appIcon, item.imagePath]) {
        final resolved = _iconName(name);
        if (resolved != null) names.add(resolved);
      }
      if (item.appIcon.isEmpty && item.desktopEntry.isNotEmpty) {
        entries.add(item.desktopEntry);
      }
    }
    _iconBytes.resolve(names);
    _iconPaths.resolve(entries);
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
    _iconBytes.dispose();
    _iconPaths.dispose();
    if (_ownsSettings) unawaited(_settings.close());
    super.dispose();
  }
}

Future<Map<String, Uint8List>> _lookupIconBytes(List<String> names) async {
  final bytes = await barIconChannel.invokeMapMethod<String, Uint8List>(
    'lookupTray',
    [
      for (final name in names) [name, ''],
    ],
  );
  return {
    for (final name in names)
      if (bytes?['\n$name'] case final icon? when icon.isNotEmpty) name: icon,
  };
}

/// Icon names stay names; paths and file URIs become absolute paths.
String? _iconName(String value) {
  if (value.isEmpty) return null;
  if (value.startsWith('file://')) {
    try {
      return Uri.parse(value).toFilePath();
    } on FormatException {
      return null;
    } on UnsupportedError {
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
