import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'bar_theme.dart';
import 'features/account/account_profile_controller.dart';
import 'features/sidebar/right_sidebar.dart';
import 'features/sidebar/sidebar_backend.dart';
import 'features/battery/bar_battery.dart';
import 'features/media/bar_media.dart';
import 'features/system/system_backend.dart';
import 'features/clock/bar_clock.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/popups/bar_popup.dart';
import 'features/resources/bar_resources.dart';
import 'features/resources/resource_data.dart';
import 'features/tray/bar_tray.dart';
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
    this.account,
    this.onOpenSettingsPage,
    this.showTray = false,
    this.onOpenSettings = openRemyaSettings,
    this.onOpenPowerSettings = _openPowerSettings,
  });

  final SettingsThemeController preferences;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final AccountProfileController? account;
  final Future<void> Function(String page)? onOpenSettingsPage;
  final bool showTray;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenPowerSettings;

  @override
  State<RemyaBarApp> createState() => _RemyaBarAppState();
}

class _RemyaBarAppState extends State<RemyaBarApp> {
  SystemSnapshot? _pillSnapshot;
  Timer? _pillRefresh;
  final _tray = GlobalKey<BarTrayState>();
  SidebarBackend? _sidebar;
  bool _sidebarOpen = false;
  bool _fullscreen = false;
  bool _checkingFullscreen = false;
  Timer? _fullscreenCheck;
  Timer? _fullscreenReconcile;

  void _scheduleFullscreenCheck() {
    _fullscreenCheck ??= Timer(const Duration(milliseconds: 50), () {
      _fullscreenCheck = null;
      unawaited(_checkFullscreen());
    });
  }

  Future<void> _checkFullscreen() async {
    if (_checkingFullscreen || !mounted) return;
    _checkingFullscreen = true;
    try {
      final geometry = await _window.invokeMapMethod<String, int>('output');
      if (geometry == null || !mounted) return;
      final hidden = await widget.hyprland!.isOutputFullscreen(
        geometry['x']!,
        geometry['y']!,
      );
      if (mounted && hidden != _fullscreen) {
        await _window.invokeMethod<void>('setFullscreen', hidden);
        _fullscreen = hidden;
      }
    } catch (error) {
      debugPrint('Bar fullscreen state: $error');
    } finally {
      _checkingFullscreen = false;
    }
  }

  String? _sidebarOutput;

  Map<String, Object?> get _sidebarData => {
    'account': widget.account?.data ?? const {},
    ...?_sidebar?.data,
  };

  Future<void> _toggleSidebar(
    Rect anchor,
    double scale, {
    String? focusedOutput,
  }) async {
    if (_fullscreen) return;
    if (_sidebarOpen) {
      _sidebarOpen = false;
      _sidebar?.close();
      await BarPopup.hide(kind: 'sidebar');
      return;
    }
    _sidebar ??= SidebarBackend()..addListener(_updateSidebar);
    _sidebarOpen = true;
    try {
      final monitor = await _sidebarMonitor();
      if (!mounted || !_sidebarOpen) return;
      if (focusedOutput != null && monitor?['name'] != focusedOutput) {
        _sidebarOpen = false;
        return;
      }
      _sidebarOutput = monitor?['name'] as String?;
      final reserved = monitor?['reserved'];
      final reservedHeight = switch (reserved) {
        [_, final int top, _, final int bottom] => top + bottom,
        _ => null,
      };
      await BarPopup.show(
        kind: 'sidebar',
        anchor: anchor,
        size: sidebarSize,
        data: {
          ..._sidebarData,
          'scale': scale,
          'reservedHeight': reservedHeight,
        },
        theme: widget.preferences.theme,
      );
      if (_sidebarOpen && mounted) _sidebar?.open(_sidebarOutput);
    } catch (error) {
      _sidebarOpen = false;
      _sidebar?.close();
      debugPrint('Sidebar: $error');
    }
  }

  static const _window = MethodChannel('top.remya.bar/window');

  Future<Map?> _sidebarMonitor() async {
    final hyprland = widget.hyprland;
    if (hyprland == null) return null;
    final geometry = await _window.invokeMapMethod<String, int>('output');
    final monitors = jsonDecode(await hyprland.request('j/monitors'));
    if (geometry == null || monitors is! List) return null;
    final matches = monitors.whereType<Map>().where(
      (monitor) =>
          monitor['x'] == geometry['x'] && monitor['y'] == geometry['y'],
    );
    return matches.length == 1 ? matches.single : null;
  }

  void _updateSidebar() {
    if (!_sidebarOpen) return;
    unawaited(
      BarPopup.update(
        kind: 'sidebar',
        anchor: const Rect.fromLTWH(0, 0, 1, 1),
        size: sidebarSize,
        data: _sidebarData,
        theme: widget.preferences.theme,
      ).catchError((Object error) => debugPrint('Sidebar update: $error')),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.system case final system?) {
      _pillSnapshot = system.resourceSnapshot;
      system.addListener(_showFirstResourceSample);
      _pillRefresh = Timer.periodic(const Duration(seconds: 3), (_) {
        final next = system.resourceSnapshot;
        if (!identical(_pillSnapshot, next)) {
          setState(() => _pillSnapshot = next);
        }
      });
    }
    if (widget.hyprland case final hyprland?) {
      hyprland.addListener(_scheduleFullscreenCheck);
      _fullscreenReconcile = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkFullscreen(),
      );
      _scheduleFullscreenCheck();
    }
    widget.account?.addListener(_updateSidebar);
    widget.preferences.addListener(_updateSidebar);
    _window.setMethodCallHandler((call) async {
      if (call.method != 'toggleSidebar') throw MissingPluginException();
      final hyprland = widget.hyprland;
      if (hyprland == null) return;
      final active = jsonDecode(await hyprland.request('j/activeworkspace'));
      if (mounted && active is Map && active['monitor'] is String) {
        await _toggleSidebar(
          const Rect.fromLTWH(0, 0, 1, 1),
          MediaQueryData.fromView(View.of(context)).textScaler.scale(1),
          focusedOutput: active['monitor'] as String,
        );
      }
    });
    BarPopup.channel.setMethodCallHandler(_popupAction);
  }

  void _showFirstResourceSample() {
    final next = widget.system?.resourceSnapshot;
    if (!BarResources.hasData(_pillSnapshot) && BarResources.hasData(next)) {
      setState(() => _pillSnapshot = next);
    }
  }

  Future<void> _popupAction(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final args = call.arguments;
    if (args is! Map) throw const FormatException('Invalid popup action');
    final action = args['action'];
    if (action == 'sidebar.closed') {
      _sidebarOpen = false;
      _sidebar?.close();
    } else if (action == 'sidebar.settings') {
      final page = args['target'];
      if (page is! String ||
          !const {
            'remya-bar',
            'wifi',
            'bluetooth',
            'sound-volume',
            'power',
          }.contains(page)) {
        throw const FormatException('Invalid Settings page');
      }
      await (widget.onOpenSettingsPage ??
          (page) => openRemyaSettings(page: page))(page);
      await BarPopup.hide(kind: 'sidebar');
    } else if (action is String && action.startsWith('sidebar.')) {
      final sidebar = _sidebar;
      if (!_sidebarOpen || sidebar == null) {
        throw StateError('Sidebar is closed');
      }
      await sidebar.perform(args, _sidebarOutput);
    } else if (action == 'media.volume' &&
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
    } else if (action is String && action.startsWith('tray.')) {
      await _tray.currentState?.popupAction(args);
    } else if (action == 'resources.monitor') {
      await openSystemMonitor();
      await BarPopup.hide(kind: 'resources');
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
    _fullscreenCheck?.cancel();
    _fullscreenReconcile?.cancel();
    widget.hyprland?.removeListener(_scheduleFullscreenCheck);
    _pillRefresh?.cancel();
    _sidebar?.dispose();
    widget.account?.removeListener(_updateSidebar);
    widget.account?.dispose();
    widget.preferences.removeListener(_updateSidebar);
    _window.setMethodCallHandler(null);
    widget.system?.removeListener(_showFirstResourceSample);
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
                pillSnapshot: _pillSnapshot,
                tray: widget.showTray ? BarTray(key: _tray) : null,
                onOpenSettings: widget.onOpenSettings,
                onToggleSidebar: _toggleSidebar,
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
    required this.onToggleSidebar,
    required this.pillSnapshot,
    this.system,
    this.tray,
  });

  final String? error;
  final SystemSnapshot? pillSnapshot;
  final SystemBackend? system;
  final Widget? tray;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function(Rect, double) onToggleSidebar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Layer-shell may configure a temporary 1-pixel width during startup.
      if (constraints.maxWidth < 40) return const SizedBox.shrink();
      final showMedia =
          constraints.maxWidth >= 720 && system?.players.isNotEmpty == true;
      final resourceBudget =
          constraints.maxWidth / 2 - 128 - (showMedia ? BarMedia.width + 4 : 0);
      final compact =
          BarResources.widthFor(context, snapshot: pillSnapshot) >
          resourceBudget;
      final resourceWidth = BarResources.widthFor(
        context,
        compact: compact,
        snapshot: pillSnapshot,
      );
      final showResources =
          resourceWidth > 0 && resourceWidth <= resourceBudget;
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
          if (showMedia || showResources)
            Align(
              alignment: .centerLeft,
              child: Row(
                mainAxisSize: .min,
                spacing: 4,
                children: [
                  if (showMedia)
                    SizedBox(
                      width: BarMedia.width,
                      child: BarMedia(
                        players: system!.players,
                        output: system!.mediaOutput,
                        onAction: system!.mediaAction,
                      ),
                    ),
                  if (showResources)
                    SizedBox(
                      width: resourceWidth,
                      child: BarResources(
                        snapshot: pillSnapshot,
                        cardSnapshot: system?.resourceSnapshot,
                        compact: compact,
                      ),
                    ),
                ],
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
                if (tray != null && constraints.maxWidth >= 700)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (constraints.maxWidth / 2 - 225).clamp(44, 290),
                    ),
                    child: tray,
                  ),
                SettingsButton(onOpen: onOpenSettings),
                if (constraints.maxWidth >= (error == null ? 80 : 100))
                  BarSidebarButton(onToggle: onToggleSidebar),
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
