import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../../src/rust/system_bridge/frb_generated.dart';

export '../../src/rust/system_bridge/api.dart';

class SystemBackend extends ChangeNotifier {
  final _settings = SettingsClient();
  Timer? _timer;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshingPower = false;
  bool isPowerSaver = false;
  api.BatterySnapshot? battery;

  static Future<void> initialize() => SystemRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_bar_system.so',
    ),
  );

  void start() {
    if (_disposed || _timer != null) return;
    void refresh() {
      unawaited(_refresh());
      unawaited(_refreshPower());
    }

    refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final next = (await api.batteries()).firstOrNull;
      if (_disposed || next == battery) return;
      battery = next;
      notifyListeners();
    } catch (failure) {
      if (_disposed) return;
      debugPrint('System backend: $failure');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshPower() async {
    if (_disposed || _refreshingPower) return;
    _refreshingPower = true;
    try {
      final power = await _settings.readPower();
      final system = power['system'];
      if (_disposed || power['available'] != true || system is! Map) return;
      final profile = system['profile'];
      if (profile is! String) return;
      final next = profile == 'power-saver';
      if (next == isPowerSaver) return;
      isPowerSaver = next;
      notifyListeners();
    } catch (failure) {
      if (!_disposed) debugPrint('Settings power: $failure');
    } finally {
      _refreshingPower = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_settings.close());
    super.dispose();
  }
}
