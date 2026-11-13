import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import '../settings/bar_preferences.dart';

import '../hyprland/hyprland_backend.dart';

/// Hyprland marks the virtual device as main as soon as it sends a key.
class KeyboardDevice {
  final _settings = SettingsClient();
  late final _preferences = BarPreferences(client: _settings);
  String? _physical;
  bool _preview = true;

  Future<void> close() => _settings.close();

  Future<bool> _readPreview() async {
    try {
      _preview = await _preferences.readKeyboardPreview().timeout(
        const Duration(milliseconds: 500),
      );
    } catch (error) {
      debugPrint('Keyboard preview Settings: $error');
    }
    return _preview;
  }

  Future<Map<String, Object?>> read(
    HyprlandBackend backend, {
    int? select,
  }) async {
    final devices = jsonDecode(await backend.request('j/devices')) as Map;
    final keyboards = (devices['keyboards'] as List).whereType<Map>().where(
      (device) =>
          device['name'] is String &&
          !(device['name'] as String).startsWith('hl-virtual-keyboard'),
    );
    final device =
        keyboards.where((device) => device['main'] == true).firstOrNull ??
        keyboards.where((device) => device['name'] == _physical).firstOrNull ??
        keyboards.lastOrNull;
    _physical = device?['name'] as String?;
    if (_physical case final String name when select != null) {
      if (select < 0 || select >= 32 || !RegExp(r'^[^\s;]+$').hasMatch(name)) {
        throw const FormatException('Invalid keyboard layout');
      }
      if ((await backend.request('switchxkblayout $name $select')).trim() !=
          'ok') {
        throw StateError('Could not switch keyboard layouts');
      }
    }
    const fields = ['rules', 'model', 'layout', 'variant', 'options'];
    Future<String?> option(String key) async {
      final response = jsonDecode(
        await backend.request('j/getoption input:kb_$key'),
      );
      final value = response is Map ? response['str'] : null;
      return value is String && value.isNotEmpty && value != '[[EMPTY]]'
          ? value
          : null;
    }

    final (file, preview) = await (option('file'), _readPreview()).wait;
    final names = device != null
        ? {for (final field in fields) field: device[field]}
        : Map.fromIterables(fields, await Future.wait(fields.map(option)));
    return {
      'config': {
        ...names,
        'group': select ?? device?['active_layout_index'] ?? 0,
        if (file != null)
          'file': file.startsWith('~/')
              ? '${Platform.environment['HOME']}${file.substring(1)}'
              : file,
      },
      'caps': device?['capsLock'] == true,
      'num': device?['numLock'] == true,
      'physical': _physical != null,
      'preview': preview,
    };
  }
}
