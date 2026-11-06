import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'bar_theme.dart';
import 'features/battery/bar_battery.dart';
import 'features/media/bar_media.dart';
import 'features/system/system_backend.dart';
import 'features/clock/bar_clock.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/popups/bar_popup.dart';
import 'features/settings/settings_button.dart';
import 'widgets/bar_tooltip.dart';
import 'widgets/bar_hover_card.dart';

Future<void> _openPowerSettings() => openRemyaSettings(page: 'power');

class RemyaBarApp extends StatefulWidget {
  const RemyaBarApp({
    super.key,
    required this.preferences,
    this.hyprland,
    this.system,
    this.onOpenSettings = openRemyaSettings,
    this.onOpenPowerSettings = _openPowerSettings,
  });

  final SettingsThemeController preferences;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenPowerSettings;

  @override
  State<RemyaBarApp> createState() => _RemyaBarAppState();
}

class _RemyaBarAppState extends State<RemyaBarApp> {
  @override
  void initState() {
    super.initState();
    BarPopup.channel.setMethodCallHandler(_popupAction);
  }

  Future<void> _popupAction(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final args = call.arguments;
    if (args is! Map) throw const FormatException('Invalid popup action');
    final action = args['action'];
    if (action == 'media.volume' &&
        args['output'] is String &&
        args['percent'] is num) {
      final system = widget.system;
      if (system == null) throw StateError('Audio output unavailable');
      await system.setMediaVolume(
        args['output'] as String,
        (args['percent'] as num).toDouble(),
      );
    } else if (action is String &&
        action.startsWith('media.') &&
        args['player'] is String) {
      final system = widget.system;
      if (system == null) throw StateError('Media unavailable');
      final player = args['player'] as String;
      if (action == 'media.seek' &&
          args['track'] is String &&
          args['seconds'] is num) {
        await system.mediaSeek(
          player,
          args['track'] as String,
          (args['seconds'] as num).toDouble(),
        );
      } else {
        await system.mediaAction(player, action.substring(6));
      }
    } else if (action == 'battery.settings') {
      await widget.onOpenPowerSettings();
      await BarPopup.hide(kind: 'battery');
    } else if (action == 'battery.profile' || action == 'battery.autoSaver') {
      final system = widget.system;
      if (system == null) throw StateError('Power controls unavailable');
      await system.setBatteryPower(action as String, args['value']);
    } else {
      throw const FormatException('Invalid popup action');
    }
  }

  @override
  void dispose() {
    BarPopup.channel.setMethodCallHandler(null);
    widget.preferences.dispose();
    widget.hyprland?.dispose();
    widget.system?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.preferences, widget.system]),
      builder: (context, _) => BarPopupScope(
        theme: widget.preferences.theme,
        child: MaterialApp(
          title: "Remy'a Bar",
          debugShowCheckedModeBanner: false,
          theme: barTheme(widget.preferences.theme.theme(.light)),
          darkTheme: barTheme(widget.preferences.theme.theme(.dark)),
          themeMode: widget.preferences.theme.mode,
          home: ClipRRect(
            borderRadius: .circular(20),
            child: Scaffold(
              body: _BarContent(
                error: widget.preferences.error,
                system: widget.system,
                onOpenSettings: widget.onOpenSettings,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.error,
    required this.onOpenSettings,
    this.system,
  });

  final String? error;
  final SystemBackend? system;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Layer-shell may configure a temporary 1-pixel width during startup.
      if (constraints.maxWidth < 40) return const SizedBox.shrink();
      return Stack(
        fit: .expand,
        children: [
          if (constraints.maxWidth >= 200)
            Positioned.fill(
              left: error == null ? 40 : 60,
              right: error == null ? 40 : 60,
              child: Center(
                child: BarClock(showSeconds: system?.showClockSeconds ?? true),
              ),
            ),
          if (system case final backend?
              when constraints.maxWidth >= 720 && backend.players.isNotEmpty)
            Align(
              alignment: .centerLeft,
              child: SizedBox(
                width: BarMedia.width,
                child: BarMedia(
                  players: backend.players,
                  output: backend.mediaOutput,
                  onAction: backend.mediaAction,
                ),
              ),
            ),
          Align(
            alignment: .centerRight,
            child: Row(
              mainAxisSize: .min,
              children: [
                if (error != null && constraints.maxWidth >= 60)
                  BarTooltip(
                    message: 'Theme unavailable',
                    child: const Icon(Icons.warning_amber_rounded, size: 20),
                  ),
                if (constraints.maxWidth >= 440 &&
                    system?.battery?.percent != null)
                  Padding(
                    padding: const .only(right: 4),
                    child: _BatteryWithCard(system: system!),
                  ),
                SettingsButton(onOpen: onOpenSettings),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _BatteryWithCard extends StatelessWidget {
  const _BatteryWithCard({required this.system});

  final SystemBackend system;

  @override
  Widget build(BuildContext context) {
    final battery = system.battery;
    return BarHoverCard(
      kind: 'battery',
      size: const Size(420, 506),
      data: {
        'present': battery != null,
        'percent': battery?.percent,
        'status': battery?.state,
        'secondsRemaining': battery?.remainingSeconds,
        'powerWatts': battery?.powerWatts,
        'healthPercent': battery?.healthPercent,
        'cycleCount': battery?.cycleCount,
        'power': system.batteryPower,
      },
      child: BarBattery(battery: battery, isPowerSaver: system.isPowerSaver),
    );
  }
}
