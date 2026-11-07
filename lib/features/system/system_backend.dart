import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  final _soundReconcile = Stopwatch();
  bool _refreshingSound = false;
  bool _writingSound = false;
  int _soundRevision = 0;
  Map<String, Object?> mediaOutput = const {};
  List<api.MediaPlayerSnapshot> players = const [];
  bool _refreshingMedia = false;
  String? mediaError;
  StreamSubscription<SettingsChange>? _settingsChanges;
  bool _writingPower = false;
  int _powerRevision = 0;
  bool _refreshingClock = false;
  bool showClockSeconds = true;
  bool _refreshingLayout = false;
  BarLayout layout = BarLayout.defaults;
  bool _refreshingStatus = false;
  int _ticks = 0;

  /// Wi-Fi radio and Bluetooth power for the quick settings toggle; null when
  /// Settings cannot report them.
  ({bool? wifi, bool? bluetooth}) quickStatus = (wifi: null, bluetooth: null);
  Map<String, Object?> batteryPower = const {};
  bool isPowerSaver = false;
  api.BatterySnapshot? get battery => resourceSnapshot?.batteries.firstOrNull;
  api.SystemSnapshot? resourceSnapshot;

  static Future<void> initialize() => SystemRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_bar_system.so',
    ),
  );

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(
      _settings.ensureIdleDaemon().catchError((Object error) {
        if (!_disposed) debugPrint('hypridle startup: $error');
      }),
    );
    _settingsChanges = _settings.changes.listen((change) {
      switch (change.topic) {
        case barClockSecondsSettingId:
          unawaited(_refreshClockPreference());
        case barLayoutSettingId:
          unawaited(_refreshLayout());
        case 'network' || 'bluetooth':
          unawaited(_refreshQuickStatus());
        case 'power':
          unawaited(_refreshPower());
        case 'sound':
          unawaited(_refreshSound(force: true));
      }
    }, onError: (Object error) => debugPrint('Settings changes: $error'));
    void refresh() {
      unawaited(_refresh());
      unawaited(_refreshMedia());
      unawaited(_refreshPower());
      unawaited(_refreshClockPreference());
      unawaited(_refreshLayout());
      if (_ticks++ % 5 == 0) unawaited(_refreshQuickStatus());
    }

    refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final next = await api.hardwareSnapshot();
      if (_disposed) return;
      resourceSnapshot = next;
      notifyListeners();
    } catch (failure) {
      if (!_disposed) debugPrint('System hardware: $failure');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshClockPreference() async {
    if (_disposed || _refreshingClock) return;
    _refreshingClock = true;
    try {
      final next = await _settings.readBarClockSeconds();
      if (_disposed || next == showClockSeconds) return;
      showClockSeconds = next;
      notifyListeners();
    } catch (failure) {
      if (!_disposed) debugPrint('Settings clock: $failure');
    } finally {
      _refreshingClock = false;
    }
  }

  // Errors keep the last valid layout, like the theme.
  Future<void> _refreshLayout() async {
    if (_disposed || _refreshingLayout) return;
    _refreshingLayout = true;
    try {
      final next = await _settings.readBarLayout();
      if (_disposed || next == layout) return;
      layout = next;
      notifyListeners();
    } catch (failure) {
      if (!_disposed) debugPrint('Settings bar layout: $failure');
    } finally {
      _refreshingLayout = false;
    }
  }

  Future<void> _refreshQuickStatus() async {
    if (_disposed || _refreshingStatus) return;
    _refreshingStatus = true;
    Future<Map?> read(Future<Map> request) =>
        request.then<Map?>((value) => value).catchError((Object error) {
          debugPrint('Settings quick status: $error');
          return null;
        });
    try {
      final (network, bluetooth) = await (
        read(_settings.readNetwork()),
        read(_settings.readBluetooth()),
      ).wait;
      final adapters = bluetooth?['adapters'];
      final next = (
        wifi: network?['wifi_enabled'] as bool?,
        bluetooth: adapters is List && adapters.isNotEmpty
            ? adapters.any(
                (adapter) => adapter is Map && adapter['powered'] == true,
              )
            : null,
      );
      if (_disposed || next == quickStatus) return;
      quickStatus = next;
      notifyListeners();
    } finally {
      _refreshingStatus = false;
    }
  }

  Future<void> _refreshPower() async {
    if (_disposed || _refreshingPower || _writingPower) return;
    _refreshingPower = true;
    final revision = _powerRevision;
    try {
      final power = await _settings.readPower();
      if (revision == _powerRevision) _applyPower(power);
    } catch (failure) {
      if (revision == _powerRevision) _applyPower(const {});
      if (!_disposed) debugPrint('Settings power: $failure');
    } finally {
      _refreshingPower = false;
    }
  }

  void _applyPower(Map<String, Object?> power) {
    if (_disposed) return;
    final system = power['system'];
    final saved = power['saved'];
    final profile = system is Map ? system['profile'] : null;
    final rawProfiles = system is Map ? system['profiles'] : null;
    final profiles = rawProfiles is List
        ? rawProfiles.whereType<String>().toList()
        : const <String>[];
    final previousProfiles = batteryPower['profiles'] as List<String>?;
    final battery = system is Map ? system['battery'] : null;
    final next = <String, Object?>{
      'available': power['available'] == true,
      'conflict': power['conflict'] == true,
      'profile': profile,
      'profiles': listEquals(profiles, previousProfiles)
          ? previousProfiles
          : profiles,
      'onBattery': battery is Map ? battery['on_battery'] : null,
      'threshold': saved is Map ? saved['threshold'] : null,
    };
    if (mapEquals(next, batteryPower)) return;
    batteryPower = next;
    if (power['available'] == true && profile is String) {
      isPowerSaver = profile == 'power-saver';
    }
    notifyListeners();
  }

  Future<void> setBatteryPower(String action, Object? value) async {
    if (_disposed || _writingPower) throw StateError('Power controls busy');
    if (batteryPower['available'] != true || batteryPower['conflict'] == true) {
      throw StateError('Power controls unavailable');
    }
    final profiles = batteryPower['profiles'] as List<String>;
    final (setting, requested) = switch (action) {
      'battery.profile' when value is String && profiles.contains(value) => (
        'power.5a4f0131',
        value,
      ),
      'battery.autoSaver' when value is bool => (
        energySaverOnThresholdId,
        value,
      ),
      _ => throw const FormatException('Invalid battery power action'),
    };
    _writingPower = true;
    _powerRevision++;
    try {
      _applyPower(await _settings.setPower(setting, requested));
    } finally {
      _writingPower = false;
    }
  }

  Future<void> _refreshMedia() async {
    if (_disposed || _refreshingMedia) return;
    _refreshingMedia = true;
    try {
      final next = await api.mediaPlayers();
      if (_disposed) return;
      if (!listEquals(players, next) || mediaError != null) {
        players = next;
        mediaError = null;
        notifyListeners();
      }
      unawaited(_refreshSound());
    } catch (error) {
      if (!_disposed && mediaError == null) {
        mediaError = 'Media status unavailable';
        debugPrint('Media status: $error');
        notifyListeners();
      }
    } finally {
      _refreshingMedia = false;
    }
  }

  Future<void> _refreshSound({bool force = false}) async {
    if (_disposed || _refreshingSound || _writingSound || players.isEmpty) {
      return;
    }
    if (!force &&
        _soundReconcile.isRunning &&
        _soundReconcile.elapsed < const Duration(seconds: 5)) {
      return;
    }
    _soundReconcile
      ..reset()
      ..start();
    _refreshingSound = true;
    final revision = _soundRevision;
    try {
      final sound = await _settings.readSound();
      if (revision == _soundRevision) _applySound(sound);
    } catch (failure) {
      if (revision == _soundRevision) _applySound(const {});
      if (!_disposed) debugPrint('Settings sound: $failure');
    } finally {
      _refreshingSound = false;
    }
  }

  void _applySound(Map<String, Object?> sound) {
    if (_disposed) return;
    final system = sound['system'];
    var output = const <String, Object?>{};
    final name = system is Map ? system['default_output'] : null;
    if (sound['available'] == true &&
        system is Map &&
        name is String &&
        name.isNotEmpty) {
      final devices = system['devices'];
      final device = devices is List
          ? devices
                .whereType<Map>()
                .where(
                  (device) =>
                      device['name'] == name && device['direction'] == 'output',
                )
                .firstOrNull
          : null;
      final preferences = device?['preferences'];
      final channels = preferences is Map ? preferences['channels'] : null;
      if (channels is List &&
          channels.isNotEmpty &&
          channels.every((value) => value is int && value >= 0)) {
        output = {
          'name': name,
          'description': device?['description'],
          'percent': channels.cast<int>().reduce(math.max) * 100 / 65536,
          'muted': (preferences as Map)['muted'] == true,
        };
      }
    }
    if (mapEquals(output, mediaOutput)) return;
    mediaOutput = output;
    notifyListeners();
  }

  Future<void> setMediaVolume(String output, double percent) async {
    if (_disposed ||
        _writingSound ||
        output != mediaOutput['name'] ||
        !percent.isFinite ||
        percent < 0 ||
        percent > 100) {
      throw StateError('Audio output or volume unavailable');
    }
    _writingSound = true;
    _soundRevision++;
    try {
      _applySound(
        await _settings.changeSound(soundOutputVolumeSettingId, {
          'name': output,
          'percent': percent,
        }),
      );
    } finally {
      _writingSound = false;
    }
  }

  Future<void> mediaAction(String busName, String action) async {
    await api.mediaAction(busName: busName, action: action);
    if (!_disposed) await _refreshMedia();
  }

  Future<void> mediaSeek(String busName, String track, double seconds) async {
    await api.mediaSeek(busName: busName, track: track, seconds: seconds);
    if (!_disposed) await _refreshMedia();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_settingsChanges?.cancel());
    unawaited(_settings.close());
    super.dispose();
  }
}
