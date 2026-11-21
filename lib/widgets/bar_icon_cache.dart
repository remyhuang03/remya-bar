import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const barIconChannel = MethodChannel('top.remya.bar/icons');
const _retryDelay = Duration(seconds: 15);

final StreamController<void> _themeChanges = StreamController<void>.broadcast(
  onListen: () => barIconChannel.setMethodCallHandler((call) async {
    if (call.method == 'themeChanged') _themeChanges.add(null);
  }),
  onCancel: () => barIconChannel.setMethodCallHandler(null),
);

/// Emits whenever GTK reports an icon theme change on [barIconChannel].
Stream<void> get barIconThemeChanges => _themeChanges.stream;

Future<Map<String, String>> lookupBarIconPaths(List<String> keys) async {
  final paths = await barIconChannel.invokeMapMethod<String, String>(
    'lookup',
    keys,
  );
  return {
    for (final entry in paths?.entries ?? const <MapEntry<String, String>>[])
      if (entry.value.startsWith('/') &&
          entry.value.toLowerCase().endsWith('.png'))
        entry.key: entry.value,
  };
}

/// Batches lookups and bounds both successful and unsuccessful results by LRU.
class BarIconCache<T extends Object> {
  BarIconCache({
    required this.lookup,
    required this.onChanged,
    this.maxEntries = 512,
    this.maxBytes = 16 * 1024 * 1024,
    this.size,
    this.refreshAfter,
    this.retryOnIdle = false,
    this.now = DateTime.now,
  }) : assert(maxEntries > 0);

  final Future<Map<String, T>> Function(List<String>) lookup;
  final VoidCallback onChanged;
  final int maxEntries;
  final int maxBytes;
  final int Function(T)? size;
  final Duration? Function(String)? refreshAfter;
  final bool retryOnIdle;
  final DateTime Function() now;

  final _entries = <String, ({T? value, DateTime? expires, int bytes})>{};
  var _keys = <String>{};
  int _bytes = 0;
  int _generation = 0;
  bool _loading = false;
  bool _pending = false;
  bool _disposed = false;
  Timer? _timer;
  StreamSubscription<void>? _theme;

  T? operator [](String? key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key!] = entry;
    return entry.value;
  }

  void resolve(Set<String> keys) {
    if (_disposed) return;
    _theme ??= _themeChanges.stream.listen((_) => _invalidate());
    _pending |= !setEquals(_keys, keys);
    _keys = keys;
    _drain();
  }

  void _invalidate() {
    final hadIcons = _entries.values.any((entry) => entry.value != null);
    _generation++;
    _entries.clear();
    _bytes = 0;
    _pending = true;
    if (hadIcons) onChanged();
    _drain();
  }

  void _drain() {
    if (_loading || _disposed) return;
    _pending = false;
    _timer?.cancel();
    final keys = <String>[];
    final time = now();
    for (final key in _keys) {
      final entry = _entries.remove(key);
      if (entry != null) _entries[key] = entry;
      final expires = entry?.expires;
      if (entry == null || (expires != null && !expires.isAfter(time))) {
        keys.add(key);
      }
    }
    if (keys.isNotEmpty) {
      unawaited(_load(keys));
    } else if (retryOnIdle) {
      _scheduleRetry();
    }
  }

  Future<void> _load(List<String> keys) async {
    _loading = true;
    final generation = _generation;
    var changed = false;
    try {
      // The native channel accepts at most 256 icons per call.
      for (var offset = 0; offset < keys.length; offset += 256) {
        final batch = keys.sublist(
          offset,
          (offset + 256).clamp(0, keys.length),
        );
        Map<String, T> result;
        try {
          result = await lookup(batch).timeout(const Duration(seconds: 5));
        } catch (error) {
          debugPrint('Bar icon lookup: $error');
          result = {};
        }
        if (_disposed || generation != _generation) return;
        for (final key in batch) {
          if (!_keys.contains(key)) continue;
          final value = result[key];
          final bytes = value == null ? 0 : size?.call(value) ?? 0;
          final accepted = bytes <= maxBytes ? value : null;
          final ttl = accepted == null ? _retryDelay : refreshAfter?.call(key);
          final previous = _entries.remove(key);
          final weight = accepted == null ? 0 : bytes;
          _entries[key] = (
            value: accepted,
            expires: ttl == null ? null : now().add(ttl),
            bytes: weight,
          );
          _bytes += weight - (previous?.bytes ?? 0);
          changed |= accepted != previous?.value;
          while (_entries.length > maxEntries || _bytes > maxBytes) {
            final evicted = _entries.remove(_entries.keys.first)!;
            _bytes -= evicted.bytes;
            changed |= evicted.value != null;
          }
        }
      }
      if (changed) onChanged();
    } finally {
      _loading = false;
      if (!_disposed) {
        if (_pending) {
          _drain();
        } else if (retryOnIdle) {
          _scheduleRetry();
        }
      }
    }
  }

  void _scheduleRetry() {
    DateTime? next;
    for (final key in _keys) {
      final expires = _entries[key]?.expires;
      if (expires != null && (next == null || expires.isBefore(next))) {
        next = expires;
      }
    }
    if (next != null) _timer = Timer(next.difference(now()), _drain);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_theme?.cancel());
    _entries.clear();
    _keys = {};
  }
}
