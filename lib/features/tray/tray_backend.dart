import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../../widgets/bar_icon_cache.dart';

/// Polls StatusNotifier items once for the bar views that display them.
class TrayBackend extends ChangeNotifier {
  TrayBackend({this.readItems = api.trayItems});

  final Future<List<api.TrayItem>> Function() readItems;
  List<api.TrayItem> _items = const [];
  Map<String, Uint8List> _icons = const {};
  Timer? _timer;
  bool _refreshing = false;
  int _generation = 0;

  List<api.TrayItem> get items => _items;

  Uint8List? iconFor(api.TrayItem item) =>
      _icons[trayIconKey(item.iconName, item.iconThemePath)];

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _items = const [];
    _icons = const {};
  }

  Future<void> _refresh() async {
    if (_refreshing || _timer == null) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final items = await readItems();
      if (generation != _generation) return;
      // Keep the lookup cadence for apps that update a PNG in place.
      final icons = await lookupTrayIcons({
        for (final item in items)
          if (item.iconName.isNotEmpty &&
              (item.iconWidth < 64 || item.iconHeight < 64))
            (item.iconName, item.iconThemePath),
      });
      if (generation != _generation) return;
      final iconsChanged = !const DeepCollectionEquality().equals(
        _icons,
        icons,
      );
      if (!iconsChanged && _sameItems(_items, items)) return;
      _items = items;
      if (iconsChanged) _icons = icons;
      notifyListeners();
    } catch (error) {
      if (generation == _generation) debugPrint('Tray: $error');
    } finally {
      _refreshing = false;
      if (!hasListeners) {
        if (_timer != null) _stop();
      } else if (generation != _generation) {
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

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
