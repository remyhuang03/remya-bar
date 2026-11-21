import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../../widgets/bar_icon_cache.dart';

/// Shares one StatusNotifier stream and icon lookup across mounted tray views.
class TrayBackend extends ChangeNotifier {
  TrayBackend({this.watchItems = api.subscribeTray});

  final Stream<List<api.TrayItem>> Function() watchItems;
  List<api.TrayItem> _items = const [];
  List<api.TrayItem>? _latestItems;
  Map<String, Uint8List> _icons = const {};
  Set<(String, String)>? _lookedUpKeys;
  StreamSubscription<List<api.TrayItem>>? _subscription;
  StreamSubscription<void>? _themeSubscription;
  Timer? _retry;
  bool _active = false;
  bool _resolving = false;
  bool _disposed = false;
  int _generation = 0;
  int _themeGeneration = 0;

  List<api.TrayItem> get items => _items;

  Uint8List? iconFor(api.TrayItem item) =>
      _icons[trayIconKey(item.iconName, item.iconThemePath)];

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_active || _disposed) return;
    _active = true;
    _themeSubscription ??= barIconThemeChanges.listen((_) => _onThemeChanged());
    _subscribe();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  void _subscribe() {
    if (!_active || _disposed || _subscription != null) return;
    final generation = _generation;
    try {
      _subscription = watchItems().listen(
        (items) => unawaited(_onSnapshot(items, generation)),
        onError: (Object error) {
          if (generation == _generation) debugPrint('Tray: $error');
        },
        onDone: () => _onDone(generation),
      );
    } catch (error) {
      if (generation == _generation) debugPrint('Tray: $error');
      _onDone(generation);
    }
  }

  void _onDone(int generation) {
    if (generation != _generation || !_active || _disposed) return;
    _subscription = null;
    _retry ??= Timer(const Duration(seconds: 1), () {
      _retry = null;
      _subscribe();
    });
  }

  void _stop() {
    _active = false;
    _generation++;
    _themeGeneration++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_themeSubscription?.cancel());
    _themeSubscription = null;
    _retry?.cancel();
    _retry = null;
    _resolving = false;
    _items = const [];
    _latestItems = null;
    _icons = const {};
    _lookedUpKeys = null;
  }

  void _onThemeChanged() {
    if (!_active || _disposed) return;
    _themeGeneration++;
    _lookedUpKeys = null;
    if (_latestItems == null) return;
    unawaited(_resolveIcons(_generation));
  }

  Future<void> _onSnapshot(List<api.TrayItem> items, int generation) async {
    if (generation != _generation || !_active || _disposed) return;
    _latestItems = items;
    final keys = _iconKeysFor(items);
    if (_lookedUpKeys != null && setEquals(_lookedUpKeys, keys)) {
      if (_sameItems(_items, items)) return;
      _items = items;
      notifyListeners();
      return;
    }
    await _resolveIcons(generation);
  }

  Future<void> _resolveIcons(int generation) async {
    if (_resolving) return;
    _resolving = true;
    try {
      while (_active && !_disposed && generation == _generation) {
        final items = _latestItems;
        if (items == null) return;
        final keys = _iconKeysFor(items);
        final themeGeneration = _themeGeneration;
        final icons = await lookupTrayIcons(keys);
        if (!_active || _disposed || generation != _generation) return;
        if (themeGeneration != _themeGeneration ||
            !setEquals(_iconKeysFor(_latestItems!), keys)) {
          // Theme or needed icon keys changed while the native lookup ran.
          continue;
        }
        _lookedUpKeys = keys;
        final latest = _latestItems!;
        final iconsChanged = !const DeepCollectionEquality().equals(
          _icons,
          icons,
        );
        final itemsChanged = !_sameItems(_items, latest);
        if (iconsChanged || itemsChanged) {
          _items = latest;
          if (iconsChanged) _icons = icons;
          notifyListeners();
        }
        return;
      }
    } catch (error) {
      if (generation == _generation) debugPrint('Tray: $error');
    } finally {
      _resolving = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}

Set<(String, String)> _iconKeysFor(List<api.TrayItem> items) => {
  for (final item in items)
    if (item.iconName.isNotEmpty &&
        (item.iconWidth < 64 || item.iconHeight < 64))
      (item.iconName, item.iconThemePath),
};

bool _sameItems(List<api.TrayItem> before, List<api.TrayItem> after) {
  if (before.length != after.length) return false;
  for (var i = 0; i < before.length; i++) {
    final a = before[i];
    final b = after[i];
    if (_fields(a) != _fields(b) || !listEquals(a.iconArgb, b.iconArgb)) {
      return false;
    }
  }
  return true;
}

Object _fields(api.TrayItem item) => (
  item.id,
  item.appId,
  item.iconThemePath,
  item.title,
  item.iconName,
  item.iconWidth,
  item.iconHeight,
  item.itemIsMenu,
  item.hasMenu,
  item.attention,
);

String trayIconKey(String name, String path) => '$path\n$name';

Future<Map<String, Uint8List>> lookupTrayIcons(
  Set<(String, String)> names,
) async {
  if (names.isEmpty) return {};
  return await barIconChannel.invokeMapMethod<String, Uint8List>('lookupTray', [
        for (final (name, path) in names) [name, path],
      ]) ??
      {};
}
