import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import 'package:remya_bar/features/settings/bar_preferences.dart';

import '../settings/bar_display.dart';

import 'osd_slider.dart';

class OsdState {
  const OsdState({
    required this.type,
    required this.value,
    this.muted = false,
    this.preMuteValue,
    this.max = osdVolumeMax,
  });

  final OsdType type;
  final int value;
  final bool muted;
  final int? preMuteValue;
  final int max;

  Map<String, Object?> toData({double scale = 1.0}) => {
    'type': type.name,
    'value': value,
    'muted': muted,
    'preMuteValue': ?preMuteValue,
    'max': max,
    'scale': scale,
  };

  @override
  bool operator ==(Object other) =>
      other is OsdState &&
      other.type == type &&
      other.value == value &&
      other.muted == muted &&
      other.preMuteValue == preMuteValue &&
      other.max == max;

  @override
  int get hashCode => Object.hash(type, value, muted, preMuteValue, max);
}

class OsdController extends ChangeNotifier {
  OsdController({
    SettingsClient? settings,
    this.timeout = const Duration(milliseconds: 1500),
  }) : _settings = settings ?? SettingsClient(),
       _ownsSettings = settings == null;

  final SettingsClient _settings;
  late final _display = BarDisplay(_settings);
  late final _preferences = BarPreferences(client: _settings);
  final bool _ownsSettings;
  final Duration timeout;

  BarOsdPreferences preferences = const BarOsdPreferences();
  OsdState? state;

  String? _output;
  int _outputRevision = 0;
  int _serviceRevision = 0;
  final _shortcuts = <_ShortcutBatch>[];
  bool _drainingShortcuts = false;
  String? _volumeOutput;
  int? _volumePercent;
  bool? _volumeMuted;
  int? _preMuteVolume;

  int? _hwBrightness;
  bool _hardwareSupported = false;
  bool _backlightOff = false;
  bool _brightnessInitialized = false;

  int? _gamma;
  int _gammaRevision = 0;
  (int?, int?)? _brightnessPreview;

  bool _disposed = false;
  bool _writingVolume = false;
  String? _writingBrightnessOutput;
  Timer? _hideTimer;
  StreamSubscription<SettingsChange>? _changes;
  StreamSubscription<bool>? _serviceChanges;

  bool get visible => state != null;

  void start({String? output}) {
    if (_disposed || _changes != null) return;
    _output = output;
    _changes = _settings.changes.listen(
      _onSettingsChange,
      onError: (Object error) => debugPrint('OSD settings stream: $error'),
    );
    _serviceChanges = _settings.serviceAvailableChanges.listen(
      _onServiceChange,
      onError: (Object error) => debugPrint('OSD Settings owner: $error'),
    );
    unawaited(_initializeState());
  }

  void updateOutput(String? output) {
    if (_disposed || _output == output) return;
    _output = output;
    _resetBrightness();
    if (state?.type != .volume) dismiss();
    unawaited(_refreshDisplay());
  }

  Future<void> _refreshDisplay() async {
    await Future.wait([_refreshBrightness(), _refreshGamma()]);
  }

  void _resetBrightness() {
    _outputRevision++;
    _hwBrightness = null;
    _hardwareSupported = false;
    _backlightOff = false;
    _brightnessInitialized = false;
    _gamma = null;
    _brightnessPreview = null;
  }

  void _onServiceChange(bool available) {
    _serviceRevision++;
    _volumeOutput = null;
    _volumePercent = null;
    _volumeMuted = null;
    _preMuteVolume = null;
    _resetBrightness();
    dismiss();
    if (available) unawaited(_initializeState());
  }

  Future<void> _initializeState() async {
    await Future.wait([
      _refreshPreferences(),
      _refreshSound(),
      _refreshDisplay(),
    ]);
  }

  void _onSettingsChange(SettingsChange change) {
    if (_disposed) return;
    final topic = change.topic;
    if (barOsdSettingIds.contains(topic)) {
      unawaited(_refreshPreferences());
      return;
    }
    switch (topic) {
      case 'sound':
        if (!_writingVolume) {
          _applySoundPayload(change.value, showChanges: _shortcuts.isEmpty);
        }
      case 'display-brightness' || 'display.5d419889':
        if (_writingBrightnessOutput != _output) {
          _applyBrightnessPayload(
            change.value,
            showChanges: _shortcuts.isEmpty,
          );
        }
      case displayGammaTopic:
        if (change.value['output'] == _output &&
            _output != null &&
            _writingBrightnessOutput != _output) {
          _applyGammaPayload(change.value, showChanges: _shortcuts.isEmpty);
        }
    }
  }

  Future<void> _refreshPreferences() async {
    final revision = _serviceRevision;
    try {
      final next = await _preferences.readOsd();
      if (_disposed || _serviceRevision != revision) return;
      preferences = next;
    } catch (error) {
      if (!_disposed) debugPrint('OSD preferences: $error');
    }
  }

  Future<void> _refreshSound() async {
    final revision = _serviceRevision;
    try {
      final sound = await _settings.readSound();
      if (_disposed || _serviceRevision != revision || _volumePercent != null) {
        return;
      }
      _applySoundPayload(sound);
    } catch (error) {
      if (!_disposed) debugPrint('OSD sound read: $error');
    }
  }

  void _applySoundPayload(
    Map<String, Object?> sound, {
    bool showChanges = false,
  }) {
    final system = sound['system'];
    final defaultOutput = system is Map ? system['default_output'] : null;
    final devices = system is Map ? system['devices'] : null;
    final device = devices is List
        ? devices.whereType<Map>().firstWhereOrNull(
            (item) =>
                item['name'] == defaultOutput && item['direction'] == 'output',
          )
        : null;
    final prefs = device?['preferences'];
    final channels = prefs is Map ? prefs['channels'] : null;
    final values = channels is List
        ? channels.whereType<int>().toList()
        : <int>[];
    if (sound['available'] != true ||
        defaultOutput is! String ||
        values.isEmpty) {
      _volumePercent = null;
      return;
    }
    final percent = (values.reduce(math.max) * 100 / 65536).round().clamp(
      0,
      150,
    );
    final muted = (prefs as Map)['muted'] == true;
    final hadBaseline = _volumePercent != null;
    final changed =
        _volumeOutput != defaultOutput ||
        _volumePercent != percent ||
        _volumeMuted != muted;
    if (!muted || _volumeOutput != defaultOutput) _preMuteVolume = percent;
    _volumeOutput = defaultOutput;
    _volumePercent = percent;
    _volumeMuted = muted;
    if (showChanges && hadBaseline && changed) _showVolume();
  }

  Future<void> _refreshBrightness() async {
    final output = _output;
    final revision = _outputRevision;
    if (output == null || output.isEmpty) return;
    try {
      final response = await _settings.call('Get', [
        'display-brightness:$output',
      ]);
      if (_disposed || _outputRevision != revision || _brightnessInitialized) {
        return;
      }
      _applyBrightnessPayload(response);
    } catch (error) {
      if (!_disposed) debugPrint('OSD brightness read: $error');
    }
  }

  int? _applyBrightnessPayload(
    Map<String, Object?> payload, {
    bool showChanges = false,
  }) {
    final output = _output;
    if (output == null || output.isEmpty) return null;
    final outputs = payload['outputs'];
    final item = payload['output'] == output
        ? payload
        : outputs is List
        ? outputs.whereType<Map>().firstWhereOrNull(
            (item) => item['output'] == output,
          )
        : null;
    if (item == null) return null;
    final rawPercent = item['percent'];
    final percent = rawPercent is int && rawPercent >= 0 && rawPercent <= 100
        ? rawPercent
        : null;
    final changed = _brightnessInitialized && _hwBrightness != percent;
    if (item.containsKey('backend')) {
      _hardwareSupported =
          item['backend'] == 'backlight' || item['backend'] == 'ddc';
      _brightnessInitialized = true;
    }
    _backlightOff = _hardwareSupported && item['raw_value'] == 0;
    _hwBrightness = percent;
    if (showChanges && changed && percent != null) {
      _show(OsdState(type: .brightness, value: percent));
    }
    return percent;
  }

  Future<void> _refreshGamma() async {
    final output = _output;
    if (output == null || output.isEmpty) return;
    final revision = _outputRevision;
    final gammaRevision = _gammaRevision;
    try {
      final gamma = await _display.readGamma(output);
      if (_disposed ||
          _outputRevision != revision ||
          _gammaRevision != gammaRevision) {
        return;
      }
      _gamma = gamma;
    } catch (error) {
      if (!_disposed) debugPrint('OSD gamma read: $error');
    }
  }

  void _applyGammaPayload(
    Map<String, Object?> payload, {
    bool showChanges = false,
  }) {
    final gamma = BarDisplay.gammaFor(_output!, payload);
    final changed = _gamma != null && _gamma != gamma;
    _gammaRevision++;
    _gamma = gamma;
    if (gamma == null && state?.type == .gamma) {
      dismiss();
    } else if (showChanges && changed && gamma != null) {
      _show(_brightnessState(.gamma, gamma, _hwBrightness));
    }
  }

  Future<void> handleShortcut(String action) {
    if (_disposed) return Future.value();
    // While earlier presses are still being written, the shown state already
    // predicts them, so this press continues from it.
    _preview(action, _drainingShortcuts ? state : null);
    final pending = _shortcuts.lastOrNull;
    if (pending != null &&
        action != 'VolumeMute' &&
        pending.action == action &&
        pending.output == _outputRevision &&
        pending.service == _serviceRevision) {
      pending.count++;
      return pending.done.future;
    }
    final batch = _ShortcutBatch(action, _outputRevision, _serviceRevision);
    _shortcuts.add(batch);
    if (!_drainingShortcuts) unawaited(_drainShortcuts());
    return batch.done.future;
  }

  /// Shows the result of a key press at once, before Core confirms it.
  /// Readbacks replace it when the queue settles; failures dismiss it.
  void _preview(String action, OsdState? predicted) {
    switch (action) {
      case 'VolumeUp' || 'VolumeDown' || 'VolumeMute':
        final base = predicted?.type == .volume ? predicted : null;
        final current = base?.value ?? _volumePercent;
        if (current == null) return;
        final muted = base?.muted ?? (_volumeMuted == true || current == 0);
        final plan = _volumePlan(current, muted, switch (action) {
          'VolumeUp' => preferences.volumeStep,
          'VolumeDown' => -preferences.volumeStep,
          _ => null,
        });
        _show(
          OsdState(
            type: .volume,
            value: plan.target,
            muted: plan.mute || plan.target == 0,
            preMuteValue: plan.mute
                ? base?.preMuteValue ?? _preMuteVolume
                : plan.target,
            max: math.max(preferences.volumeMax, plan.target),
          ),
        );
      case 'BrightnessUp' || 'BrightnessDown':
        if (!_brightnessInitialized) return;
        final (hardware, gamma) = _brightnessPreview ?? (_hwBrightness, _gamma);
        final step = preferences.brightnessStep;
        final plan = _brightnessPlan(
          hardware,
          gamma,
          action == 'BrightnessUp' ? step : -step,
          1,
        );
        if (plan == null) return;
        final nextHardware = plan.type == .brightness ? plan.target : hardware;
        final nextGamma = plan.type == .gamma ? plan.target : gamma;
        _brightnessPreview = (nextHardware, nextGamma);
        _show(_brightnessState(plan.type, plan.target, nextHardware));
    }
  }

  /// Zero volume and mute are one state: stepping down to 0 mutes, and
  /// unmuting or stepping up from 0 restores at least one step.
  ({int target, bool mute}) _volumePlan(int current, bool muted, int? delta) {
    // An externally raised level above the ceiling is kept, not cut.
    final ceiling = math.max(preferences.volumeMax, current);
    final target = switch (delta) {
      null when muted && current == 0 => preferences.volumeStep,
      null => current,
      _ => (current + delta).clamp(0, ceiling),
    };
    final mute = delta == null ? !muted : target == 0 || (muted && delta < 0);
    return (target: target, mute: mute);
  }

  /// Hardware brightness above full gamma, software gamma below it.
  ({OsdType type, int current, int target, int steps})? _brightnessPlan(
    int? brightness,
    int? gamma,
    int delta,
    int count,
  ) {
    if (delta > 0 && _backlightOff) brightness ??= 0;
    final hardware =
        _hardwareSupported &&
        brightness != null &&
        (delta < 0
            ? brightness > 0 || gamma == null
            : gamma == null || gamma == 100);
    final current = hardware ? brightness : gamma;
    if (current == null) return null;
    final floor = hardware ? 0 : math.min(gamma!, preferences.gammaMin);
    final limit = delta > 0 ? 100 : floor;
    final steps = current == limit
        ? 0
        : math.min(count, ((limit - current).abs() / delta.abs()).ceil());
    return (
      type: hardware ? .brightness : .gamma,
      current: current,
      target: (current + steps * delta).clamp(floor, 100),
      steps: steps,
    );
  }

  OsdState _brightnessState(OsdType type, int value, int? hardware) =>
      type == .gamma && value == 100 && hardware == 0
      ? const OsdState(type: .brightness, value: 0)
      : OsdState(type: type, value: value);

  Future<void> _drainShortcuts() async {
    _drainingShortcuts = true;
    while (_shortcuts.isNotEmpty) {
      final batch = _shortcuts.removeAt(0);
      try {
        if (!_disposed && _serviceRevision == batch.service) {
          switch (batch.action) {
            case 'VolumeUp':
              await _changeVolume(preferences.volumeStep * batch.count);
            case 'VolumeDown':
              await _changeVolume(-preferences.volumeStep * batch.count);
            case 'VolumeMute':
              await _changeVolume(null);
            case 'BrightnessUp' when _outputRevision == batch.output:
              await _adjustBrightness(preferences.brightnessStep, batch.count);
            case 'BrightnessDown' when _outputRevision == batch.output:
              await _adjustBrightness(-preferences.brightnessStep, batch.count);
          }
        }
        batch.done.complete();
      } catch (error, stack) {
        batch.done.completeError(error, stack);
      }
      if (!_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    _drainingShortcuts = false;
    _brightnessPreview = null;
  }

  void _showVolume() {
    final percent = _volumePercent;
    if (percent == null) return;
    _show(
      OsdState(
        type: .volume,
        value: percent,
        muted: _volumeMuted == true || percent == 0,
        preMuteValue: _preMuteVolume,
        max: math.max(preferences.volumeMax, percent),
      ),
    );
  }

  Future<void> _changeVolume(int? delta) async {
    final revision = _serviceRevision;
    if (_volumePercent == null) await _refreshSound();
    final current = _volumePercent;
    if (_disposed || _serviceRevision != revision || current == null) return;
    _writingVolume = true;
    try {
      final (:target, :mute) = _volumePlan(
        current,
        _volumeMuted == true || current == 0,
        delta,
      );
      Future<bool> write(String id, Map<String, Object?> value) async {
        final sound = await _settings.changeSound(id, value);
        if (_disposed || _serviceRevision != revision) return false;
        _applySoundPayload(sound);
        return true;
      }

      if (target != current &&
          !await write(soundOutputVolumeSettingId, {'percent': target})) {
        return;
      }
      if ((_volumeMuted == true) != mute &&
          !await write(soundOutputMutedSettingId, {'muted': mute})) {
        return;
      }
      // Later presses already show their predicted level.
      if (_shortcuts.isEmpty) _showVolume();
    } catch (error) {
      if (!_disposed && _serviceRevision == revision) {
        _volumePercent = null;
        if (state?.type == .volume) dismiss();
        debugPrint('OSD volume write: $error');
      }
    } finally {
      _writingVolume = false;
    }
  }

  Future<void> _adjustBrightness(int delta, int count) async {
    final revision = _outputRevision;
    bool isCurrent() => !_disposed && _outputRevision == revision;
    final output = _output;
    if (output == null || output.isEmpty) return;
    if (!_brightnessInitialized) await _refreshBrightness();
    if (!isCurrent() || !_brightnessInitialized) return;
    if (_gamma == null) await _refreshGamma();
    if (!isCurrent()) return;
    _writingBrightnessOutput = output;
    _gammaRevision++;
    int? previousHardware;
    try {
      while (count > 0 && isCurrent()) {
        final hardware = _hwBrightness;
        final plan = _brightnessPlan(hardware, _gamma, delta, count);
        if (plan == null) return;
        if (plan.steps == 0) {
          if (_shortcuts.isEmpty) {
            _brightnessPreview = null;
            _show(_brightnessState(plan.type, plan.current, hardware));
          }
          return;
        }
        final software = plan.type == .gamma;
        await _display.setLevel(
          output,
          hardware: hardware,
          gamma: _gamma,
          target: plan.target,
          mode: software
              ? .software
              : delta < 0
              ? .hardwareOnly
              : .hardware,
          isCurrent: isCurrent,
          previousHardware: previousHardware,
          onReadback: (hardware, gamma) {
            if (hardware != null) _backlightOff = false;
            _hwBrightness = hardware;
            _gamma = gamma;
          },
        );
        if (!isCurrent()) return;
        previousHardware = !software && plan.target == 0 ? hardware : null;
        final actual = (software ? _gamma : _hwBrightness)!;
        count -= plan.steps;
        // Intermediate and superseded readbacks would step backwards.
        if (count == 0 && _shortcuts.isEmpty) {
          _brightnessPreview = null;
          _show(_brightnessState(plan.type, actual, _hwBrightness));
        }
      }
    } catch (error) {
      if (isCurrent()) {
        _brightnessInitialized = false;
        _hwBrightness = null;
        _gamma = null;
        _brightnessPreview = null;
        if (state?.type != .volume) dismiss();
        debugPrint('OSD brightness write: $error');
      }
    } finally {
      _writingBrightnessOutput = null;
    }
  }

  void _show(OsdState next) {
    if (_disposed) return;
    final changed = state != next;
    state = next;
    _hideTimer?.cancel();
    _hideTimer = Timer(timeout, dismiss);
    if (changed) notifyListeners();
  }

  void dismiss() {
    if (_disposed || state == null) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    state = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_serviceChanges?.cancel());
    if (_ownsSettings) unawaited(_settings.close());
    super.dispose();
  }
}

class _ShortcutBatch {
  _ShortcutBatch(this.action, this.output, this.service);

  final String action;
  final int output;
  final int service;
  final done = Completer<void>();
  int count = 1;
}
