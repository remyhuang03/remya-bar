import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
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
import 'features/window/bar_active_window.dart';
import 'features/workspaces/bar_workspaces.dart';
import 'widgets/bar_groups_layout.dart';
import 'widgets/bar_tooltip.dart';

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
  bool _sidebarOpenValue = false;
  bool get _sidebarOpen => _sidebarOpenValue;
  // The toggle shows the open state, so changes rebuild the bar.
  set _sidebarOpen(bool value) {
    if (value == _sidebarOpenValue) return;
    _sidebarOpenValue = value;
    if (mounted) setState(() {});
  }

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
      system.addListener(_applyWorkspaceCount);
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
      if (call.method == 'outputChanged') {
        final geometry = Map<String, int>.from(call.arguments as Map);
        widget.hyprland?.updateOutput(x: geometry['x']!, y: geometry['y']!);
        return;
      }
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

  void _applyWorkspaceCount() {
    final count = widget.system?.layout.workspaceCount;
    if (count != null) unawaited(widget.hyprland?.setWorkspaceCount(count));
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
    if (action == 'card.state') {
      final kind = args['kind'];
      final open = args['open'];
      if (kind is! String ||
          !const {'media', 'battery', 'datetime', 'resources'}.contains(kind) ||
          open is! bool) {
        throw const FormatException('Invalid card state');
      }
      if (open) {
        BarPopup.openCard.value = kind;
      } else if (BarPopup.openCard.value == kind) {
        BarPopup.openCard.value = null;
      }
    } else if (action == 'sidebar.closed') {
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
    } else if (action == 'workspace.switch' && args['id'] is int) {
      final backend = widget.hyprland;
      if (backend == null ||
          !await backend.switchWorkspace(args['id'] as int)) {
        throw StateError('Workspace unavailable');
      }
      await BarPopup.hide(kind: workspaceOverviewKind);
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
    } else if (action == 'settings') {
      await widget.onOpenSettings();
    } else if (action == 'datetime.settings') {
      const page = 'date-time';
      await (widget.onOpenSettingsPage ??
          (page) => openRemyaSettings(page: page))(page);
      await BarPopup.hide(kind: 'datetime');
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
    widget.system?.removeListener(_applyWorkspaceCount);
    BarPopup.channel.setMethodCallHandler(null);
    widget.preferences.dispose();
    widget.hyprland?.dispose();
    widget.system?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.preferences,
        widget.hyprland,
        widget.system,
      ]),
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
                hyprland: widget.hyprland,
                system: widget.system,
                pillSnapshot: _pillSnapshot,
                sidebarOpen: _sidebarOpen,
                tray: widget.showTray ? BarTray(key: _tray) : null,
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
    required this.onToggleSidebar,
    required this.pillSnapshot,
    required this.sidebarOpen,
    this.hyprland,
    this.system,
    this.tray,
  });

  final String? error;
  final SystemSnapshot? pillSnapshot;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final Widget? tray;
  final bool sidebarOpen;
  final Future<void> Function(Rect, double) onToggleSidebar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Layer-shell may configure a temporary 1-pixel width during startup.
      final width = constraints.maxWidth;
      if (width < 40) return const SizedBox.shrink();
      final scaledWidth = width / MediaQuery.textScalerOf(context).scale(1);
      final layout = system?.layout ?? BarLayout.defaults;
      final clock = BarClock(showSeconds: system?.showClockSeconds ?? true);
      final sidebar = Row(
        mainAxisSize: .min,
        children: [
          if (error != null && width >= 60)
            const Padding(
              padding: .only(right: 8),
              child: BarTooltip(
                message: 'Theme unavailable',
                child: Icon(Icons.warning_amber_rounded, size: 20),
              ),
            ),
          BarSidebarButton(
            onToggle: onToggleSidebar,
            open: sidebarOpen,
            wifi: system?.quickStatus.wifi,
            bluetooth: system?.quickStatus.bluetooth,
            volume: (system?.mediaOutput['percent'] as num?)?.toDouble(),
            muted: system?.mediaOutput['muted'] as bool?,
          ),
        ],
      );
      if (scaledWidth < 700) {
        return Stack(
          fit: .expand,
          children: [
            if (width >= 200)
              Positioned.fill(
                left: 100,
                right: 100,
                child: Center(child: clock),
              ),
            // Transitional surfaces can be narrower than the toggle.
            Align(
              alignment: .centerRight,
              child: FittedBox(fit: .scaleDown, child: sidebar),
            ),
          ],
        );
      }
      final metrics = layout.resources;
      final compactResources = scaledWidth < 1600;
      Widget? pill(String id) => switch (id) {
        // A fixed slot, kept while no window is focused, so title changes
        // never move other pills.
        'window' when hyprland != null && hyprland!.error == null => SizedBox(
          width: BarActiveWindow.width,
          child: BarActiveWindow(
            backend: hyprland,
            showAppName: layout.windowAppName,
          ),
        ),
        'resources' when BarResources.hasData(pillSnapshot, metrics: metrics) =>
          SizedBox(
            width: BarResources.widthFor(
              context,
              compact: compactResources,
              snapshot: pillSnapshot,
              metrics: metrics,
            ),
            child: BarResources(
              snapshot: pillSnapshot,
              cardSnapshot: system?.resourceSnapshot,
              compact: compactResources,
              metrics: metrics,
            ),
          ),
        'media' when system?.players.isNotEmpty == true => ConstrainedBox(
          constraints: const .new(maxWidth: BarMedia.width),
          // The title needs room; drop the pill rather than squeeze it.
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 112
                ? const SizedBox.shrink()
                : BarMedia(
                    players: system!.players,
                    output: system!.mediaOutput,
                    error: system!.mediaError,
                    onAction: system!.mediaAction,
                  ),
          ),
        ),
        'workspaces'
            when hyprland?.connected == true &&
                hyprland?.error == null &&
                hyprland!.workspaceSlots.isNotEmpty =>
          BarWorkspaces(backend: hyprland),
        'clock' => ConstrainedBox(
          constraints: const .new(maxWidth: 180),
          child: clock,
        ),
        'tray' when tray != null => ConstrainedBox(
          constraints: const .new(maxWidth: 290),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < 44 ? const SizedBox.shrink() : tray!,
          ),
        ),
        'battery' when system?.battery?.percent?.isFinite == true => BarBattery(
          battery: system!.battery,
          isPowerSaver: system!.isPowerSaver,
          power: system!.batteryPower,
        ),
        'sidebar' => sidebar,
        _ => null,
      };
      final groups = <Widget>[];
      int? center;
      for (var i = 0; i < layout.groups.length; i++) {
        final pills = [...layout.groups[i].map(pill).nonNulls];
        if (pills.isEmpty) continue;
        if (i == layout.center) center = groups.length;
        groups.add(Row(mainAxisSize: .min, spacing: 8, children: pills));
      }
      // Overlong content scrolls instead of squeezing or dropping pills.
      return _WheelScroll(
        builder: (controller) => SingleChildScrollView(
          controller: controller,
          scrollDirection: .horizontal,
          padding: const .symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: .new(minWidth: width - 48, maxHeight: 40),
            child: BarGroupsLayout(center: center, children: groups),
          ),
        ),
      );
    },
  );
}

/// Maps vertical mouse wheel scrolling to the horizontal bar, unless a pill
/// such as the workspaces claimed the wheel event first.
class _WheelScroll extends StatefulWidget {
  const _WheelScroll({required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<_WheelScroll> createState() => _WheelScrollState();
}

class _WheelScrollState extends State<_WheelScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      final delta = event is PointerScrollEvent ? event.scrollDelta.dy : 0.0;
      if (delta == 0 ||
          !_controller.hasClients ||
          _controller.position.maxScrollExtent == 0) {
        return;
      }
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final position = _controller.position;
        _controller.jumpTo(
          (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
        );
      });
    },
    child: ScrollConfiguration(
      // A scrollbar would cover the 40-pixel pills.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: widget.builder(_controller),
    ),
  );
}
