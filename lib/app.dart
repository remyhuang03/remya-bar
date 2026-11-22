import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessException;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

import 'bar_content.dart';
import 'bar_theme.dart';
import 'features/settings/bar_settings_entry.dart';
import 'features/weather/weather_controller.dart';
import 'features/account/account_profile_controller.dart';
import 'features/ai_usage/ai_usage_backend.dart';
import 'features/ai_usage/ai_usage_data.dart';
import 'features/sidebar/right_sidebar.dart';
import 'features/sidebar/sidebar_backend.dart';
import 'features/sidebar/sidebar_app_launcher.dart';
import 'features/notifications/notification_backend.dart';
import 'features/notifications/notification_flow.dart';
import 'features/notifications/notification_toasts.dart';
import 'features/osd/osd_controller.dart';
import 'features/osd/osd_slider.dart';
import 'features/system/system_backend.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/keyboard/keyboard_device.dart';
import 'features/keyboard/keyboard_panel.dart';
import 'features/popups/bar_popup.dart';
import 'features/resources/resource_data.dart';
import 'features/tray/bar_tray.dart';
import 'features/tray/tray_backend.dart';
import 'features/workspaces/bar_workspaces.dart';

part 'app_popup_actions.dart';

Future<void> _openPowerSettings() => openRemyaSettings(page: 'power');
Future<void> _defaultLaunchScreenCapture(List<String> arguments) =>
    openRemyaScreenCapture(arguments: arguments);

class RemyaBarApp extends StatefulWidget {
  const RemyaBarApp({
    super.key,
    required this.preferences,
    required this.popup,
    this.window,
    this.hyprland,
    this.system,
    this.weather,
    this.account,
    this.aiUsage,
    this.notifications,
    this.osd,
    this.onOpenSettingsPage,
    this.tray,
    this.onOpenSettings = openRemyaSettings,
    this.onOpenPowerSettings = _openPowerSettings,
    this.onLaunchScreenCapture = _defaultLaunchScreenCapture,
    this.onOpenClipboard = openRemyaClipboard,
  });

  final SettingsThemeController preferences;
  final BarPopup popup;
  final MethodChannel? window;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final WeatherController? weather;
  final AccountProfileController? account;
  final AiUsageBackend? aiUsage;
  final NotificationBackend? notifications;
  final OsdController? osd;
  final Future<void> Function(String page)? onOpenSettingsPage;
  final TrayBackend? tray;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenPowerSettings;
  final Future<void> Function(List<String> arguments) onLaunchScreenCapture;
  final Future<void> Function() onOpenClipboard;

  @override
  State<RemyaBarApp> createState() => _RemyaBarAppState();
}

class _RemyaBarAppState extends State<RemyaBarApp> {
  BarPopup get _popup => widget.popup;
  MethodChannel? get _window => widget.window;
  final _tray = GlobalKey<BarTrayState>();
  SidebarBackend? _sidebar;
  final _keyboardDevice = KeyboardDevice();
  static const _popupAnchor = Rect.fromLTWH(0, 0, 1, 1);
  bool _sidebarOpenValue = false;
  bool get _sidebarOpen => _sidebarOpenValue;
  // The toggle shows the open state, so changes rebuild the bar.
  set _sidebarOpen(bool value) {
    if (value == _sidebarOpenValue) return;
    _sidebarOpenValue = value;
    if (mounted) setState(() {});
  }

  bool _notificationsOpenValue = false;
  bool get _notificationsOpen => _notificationsOpenValue;
  set _notificationsOpen(bool value) {
    if (value == _notificationsOpenValue) return;
    _notificationsOpenValue = value;
    if (mounted) setState(() {});
  }

  double _notificationsScale = 1;
  int? _notificationsReservedHeight;
  int _panelRequest = 0;

  bool _fullscreen = false;
  bool _desiredFullscreen = false;
  bool? _nativeFullscreen = false;
  bool _applyingFullscreen = false;
  Timer? _fullscreenRetry;
  bool _focused = false;
  int _outputRevision = 0;
  String? _outputName;

  Future<void> _loadOutput() async {
    final revision = _outputRevision;
    try {
      final geometry = await _window?.invokeMapMethod<String, int>('output');
      if (mounted && revision == _outputRevision) {
        _updateOutput(geometry);
      }
    } catch (error) {
      if (mounted) debugPrint('Bar output: $error');
    }
  }

  void _updateOutput(Object? geometry) {
    if (geometry is Map && geometry['x'] is int && geometry['y'] is int) {
      widget.hyprland?.updateOutput(
        x: geometry['x'] as int,
        y: geometry['y'] as int,
      );
    }
  }

  void _onOutputState() {
    final hyprland = widget.hyprland;
    final output = hyprland?.output;
    if (output == null) return;
    final outputChanged = _outputName != output.name;
    final fullscreenChanged = output.fullscreen != _desiredFullscreen;
    final focusedChanged = _focused != hyprland!.isFocused;
    _outputName = output.name;
    _focused = hyprland.isFocused;
    widget.osd?.updateOutput(output.name);
    widget.notifications?.setFullscreen(this, output.name, output.fullscreen);
    if (fullscreenChanged) {
      _desiredFullscreen = output.fullscreen;
      _fullscreenRetry?.cancel();
      _fullscreenRetry = null;
      unawaited(_applyFullscreen());
    }
    if (outputChanged || focusedChanged) {
      unawaited(_syncToasts());
    }
  }

  Future<void> _applyFullscreen() async {
    if (_applyingFullscreen) return;
    _applyingFullscreen = true;
    try {
      while (mounted && _nativeFullscreen != _desiredFullscreen) {
        final next = _desiredFullscreen;
        try {
          await _window?.invokeMethod<void>('setFullscreen', next);
        } catch (error) {
          if (!mounted) return;
          debugPrint('Bar fullscreen state: $error');
          _nativeFullscreen = null;
          _fullscreenRetry = Timer(const Duration(seconds: 2), () {
            _fullscreenRetry = null;
            unawaited(_applyFullscreen());
          });
          return;
        }
        if (!mounted) return;
        _nativeFullscreen = next;
        if (_fullscreen != next) {
          setState(() => _fullscreen = next);
          unawaited(_syncOsd());
          unawaited(_syncToasts());
        }
      }
    } finally {
      _applyingFullscreen = false;
    }
  }

  String? _sidebarOutput;
  String? _sidebarFocus;

  Map<String, Object?> get _sidebarData => {
    'account': widget.account?.data ?? const {},
    ...?_sidebar?.data,
  };

  Future<void> _toggleSidebar(
    Rect anchor,
    double scale, {
    String? focusedOutput,
  }) async {
    if (_fullscreen ||
        (focusedOutput != null &&
            widget.hyprland?.output?.name != focusedOutput)) {
      return;
    }
    final request = ++_panelRequest;
    if (_sidebarOpen) {
      _sidebarOpen = false;
      _sidebar?.close();
      await _popup.hide(kind: 'sidebar');
      return;
    }
    _notificationsOpen = false;
    unawaited(_syncToasts());
    _sidebar ??= SidebarBackend()..addListener(_updateSidebar);
    _sidebarOpen = true;
    try {
      final (monitor, focus) = await (_sidebarMonitor(), _focusedWindow()).wait;
      if (!mounted || !_sidebarOpen || request != _panelRequest) return;
      if (focusedOutput != null && monitor?['name'] != focusedOutput) {
        _sidebarOpen = false;
        return;
      }
      _sidebarOutput = monitor?['name'] as String?;
      _sidebarFocus = focus;
      final reserved = monitor?['reserved'];
      final reservedHeight = switch (reserved) {
        [_, final int top, _, final int bottom] => top + bottom,
        _ => null,
      };
      await _popup.show(
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
      if (_sidebarOpen && mounted && request == _panelRequest) {
        _sidebar?.open(_sidebarOutput);
      }
    } catch (error) {
      if (request == _panelRequest) {
        _sidebarOpen = false;
        _sidebar?.close();
        unawaited(_syncToasts());
      }
      debugPrint('Sidebar: $error');
    }
  }

  Future<String?> _focusedWindow() async {
    final backend = widget.hyprland;
    if (backend == null) return null;
    try {
      final active = jsonDecode(await backend.request('j/activewindow'));
      final address = active is Map ? active['address'] : null;
      return address is String && RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(address)
          ? address
          : null;
    } catch (error) {
      debugPrint('Sidebar focused window: $error');
      return null;
    }
  }

  Future<Map?> _sidebarMonitor() async {
    final hyprland = widget.hyprland;
    if (hyprland == null) return null;
    final geometry = await _window?.invokeMapMethod<String, int>('output');
    final monitors = jsonDecode(await hyprland.request('j/monitors'));
    if (geometry == null || monitors is! List) return null;
    final matches = monitors.whereType<Map>().where(
      (monitor) =>
          monitor['x'] == geometry['x'] && monitor['y'] == geometry['y'],
    );
    return matches.length == 1 ? matches.single : null;
  }

  Map<String, Object?> _notificationsData(double scale, {int? reservedHeight}) {
    final backend = widget.notifications;
    return {
      'notifications': [
        if (backend != null)
          for (final item in backend.history) backend.toData(item),
      ],
      'dnd': backend?.doNotDisturb,
      'quietReason': backend?.quietReason,
      'quietUntilMinutes': backend?.quietUntilMinutes,
      'clearCritical': backend?.clearCritical,
      'serviceError': backend?.error,
      'scale': scale,
      'reservedHeight': ?reservedHeight,
    };
  }

  Future<void> _toggleNotifications(Rect anchor, double scale) async {
    if (_fullscreen) return;
    final request = ++_panelRequest;
    if (_notificationsOpen) {
      _notificationsOpen = false;
      await _popup.hide(kind: 'notifications');
      unawaited(_syncToasts());
      return;
    }
    _sidebarOpen = false;
    _sidebar?.close();
    _notificationsOpen = true;
    _notificationsScale = scale;
    unawaited(_syncToasts());
    try {
      final monitor = await _sidebarMonitor();
      if (!mounted || !_notificationsOpen || request != _panelRequest) return;
      final reserved = monitor?['reserved'];
      _notificationsReservedHeight = switch (reserved) {
        [_, final int top, _, final int bottom] => top + bottom,
        _ => null,
      };
      await _popup.show(
        kind: 'notifications',
        anchor: anchor,
        size: const Size(420, 663),
        data: _notificationsData(
          scale,
          reservedHeight: _notificationsReservedHeight,
        ),
        theme: widget.preferences.theme,
      );
    } catch (error) {
      if (request == _panelRequest) {
        _notificationsOpen = false;
        unawaited(_syncToasts());
      }
      debugPrint('Notifications: $error');
    }
  }

  void _updateNotifications() {
    if (!_notificationsOpen) return;
    unawaited(
      _popup
          .update(
            kind: 'notifications',
            anchor: _popupAnchor,
            size: const Size(420, 663),
            data: _notificationsData(
              _notificationsScale,
              reservedHeight: _notificationsReservedHeight,
            ),
            theme: widget.preferences.theme,
          )
          .catchError(
            (Object error) => debugPrint('Notifications update: $error'),
          ),
    );
  }

  void _onNotificationsChanged() {
    _updateNotifications();
    unawaited(_syncToasts());
  }

  void _updateSidebar() {
    if (!_sidebarOpen) return;
    unawaited(
      _popup
          .update(
            kind: 'sidebar',
            anchor: const Rect.fromLTWH(0, 0, 1, 1),
            size: sidebarSize,
            data: _sidebarData,
            theme: widget.preferences.theme,
          )
          .catchError((Object error) => debugPrint('Sidebar update: $error')),
    );
  }

  void _onKeyboardLayout() {
    final hyprland = widget.hyprland;
    if (!mounted || hyprland == null || !BarPopup.keyboardOpen.value) return;
    unawaited(
      _popup
          .update(
            kind: keyboardKind,
            anchor: _popupAnchor,
            size: keyboardSize,
            data: {'refresh': hyprland.layoutChanges.value},
            theme: widget.preferences.theme,
          )
          .catchError((Object error) => debugPrint('Keyboard layout: $error')),
    );
  }

  void _updatePopupThemes() {
    _updateSidebar();
    _updateNotifications();
    if (_showingOsd) unawaited(_syncOsd());
    unawaited(
      _popup
          .update(
            kind: keyboardKind,
            anchor: _popupAnchor,
            size: keyboardSize,
            data: const {},
            theme: widget.preferences.theme,
          )
          .catchError((Object error) => debugPrint('Keyboard theme: $error')),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.system case final system?) {
      system.addListener(_applyWorkspaceCount);
      system.addListener(_applyEdge);
      _applyWorkspaceCount();
      _applyEdge();
    }
    if (widget.hyprland case final hyprland?) {
      hyprland.addListener(_onOutputState);
      hyprland.layoutChanges.addListener(_onKeyboardLayout);
      _onOutputState();
    }
    widget.account?.addListener(_updateSidebar);
    widget.notifications?.addListener(_onNotificationsChanged);
    widget.osd?.addListener(_syncOsd);
    widget.preferences.addListener(_updatePopupThemes);
    _window?.setMethodCallHandler((call) async {
      if (call.method == 'outputChanged') {
        _outputRevision++;
        _updateOutput(call.arguments);
        return;
      }
      if (call.method == 'osdShortcut') {
        final action = call.arguments;
        final osd = widget.osd;
        if (action is! String || osd == null) return;
        final hyprland = widget.hyprland;
        if (hyprland != null) {
          final active = await hyprland.focusedOutput();
          final output = hyprland.output?.name;
          if (!mounted || output == null || active != output) return;
          osd.updateOutput(output);
        }
        await osd.handleShortcut(action);
        return;
      }
      if (call.method != 'toggleSidebar') throw MissingPluginException();
      final hyprland = widget.hyprland;
      if (hyprland == null) return;
      final output = await hyprland.focusedOutput();
      if (mounted && output != null) {
        await _toggleSidebar(
          const Rect.fromLTWH(0, 0, 1, 1),
          MediaQueryData.fromView(View.of(context)).textScaler.scale(1),
          focusedOutput: output,
        );
      }
    });
    _popup.channel.setMethodCallHandler(_popupAction);
    if (widget.hyprland != null) unawaited(_loadOutput());
  }

  bool _showingToasts = false;
  Timer? _toastExit;
  bool _syncingToasts = false;
  bool _toastsDirty = false;
  bool _showingOsd = false;
  bool _syncingOsd = false;
  bool _osdDirty = false;

  Future<void> _syncOsd() async {
    final osd = widget.osd;
    if (osd == null || !mounted) return;
    osd.updateOutput(widget.hyprland?.output?.name);
    if (_syncingOsd) {
      _osdDirty = true;
      return;
    }
    _syncingOsd = true;
    try {
      final current = osd.state;
      var visible = current != null;
      final hyprland = widget.hyprland;
      if (visible && current.type == .volume && hyprland != null) {
        final output = hyprland.output?.name;
        if (output != null) {
          final focused = await hyprland.focusedOutput();
          if (!mounted) return;
          visible = focused == output && hyprland.output?.name == output;
        } else {
          visible = false;
        }
      }
      if (!visible) {
        if (_showingOsd) {
          _showingOsd = false;
          await _popup.hide(kind: osdKind);
        }
        return;
      }
      if (!mounted) return;
      final request = _showingOsd ? _popup.update : _popup.show;
      _showingOsd = true;
      await request(
        kind: osdKind,
        anchor: _popupAnchor,
        size: osdSize,
        data: current!.toData(
          scale: MediaQueryData.fromView(View.of(context)).textScaler.scale(1),
        ),
        theme: widget.preferences.theme,
      );
    } catch (error) {
      debugPrint('OSD popup: $error');
    } finally {
      _syncingOsd = false;
      if (_osdDirty) {
        _osdDirty = false;
        unawaited(_syncOsd());
      }
    }
  }

  /// One output, the focused one when the stack starts, hosts the popups until
  /// they end; it hides them while its notification card is open.
  Future<void> _syncToasts() async {
    final backend = widget.notifications;
    final output = widget.hyprland?.output?.name;
    if (backend == null || !mounted) return;
    if (_syncingToasts) {
      _toastsDirty = true;
      return;
    }
    _syncingToasts = true;
    try {
      final popups = backend.popups;
      if (popups.isNotEmpty &&
          backend.popupHost == null &&
          output != null &&
          !_fullscreen) {
        final focused = await widget.hyprland!.focusedOutput();
        if (!mounted) return;
        if (!_fullscreen && focused == widget.hyprland?.output?.name) {
          backend.claimPopups(this);
        }
      }
      final ownsStack =
          backend.popupHost == this && !_notificationsOpen && !_fullscreen;
      if (popups.isEmpty &&
          _showingToasts &&
          !_notificationsOpen &&
          !_fullscreen) {
        if (_toastExit?.isActive == true) return;
        if (_toastExit == null) {
          _toastExit = Timer(
            NotificationFlow.exitDuration + const Duration(milliseconds: 50),
            () => unawaited(_syncToasts()),
          );
          await _showToasts(const []);
          return;
        }
      }
      _toastExit?.cancel();
      _toastExit = null;
      if (!ownsStack || popups.isEmpty) {
        if (_showingToasts) {
          _showingToasts = false;
          await _popup.hide(kind: notificationToastsKind);
          if (mounted && backend.popupHost == this) await backend.hover(false);
        }
        return;
      }
      if (!mounted) return;
      await _showToasts(popups.map(backend.toData).toList());
    } catch (error) {
      debugPrint('Notification popups: $error');
    } finally {
      _syncingToasts = false;
      if (_toastsDirty) {
        _toastsDirty = false;
        unawaited(_syncToasts());
      }
    }
  }

  Future<void> _showToasts(List<Map<String, Object?>> popups) {
    final request = _showingToasts ? _popup.update : _popup.show;
    _showingToasts = true;
    return request(
      kind: notificationToastsKind,
      anchor: _popupAnchor,
      size: const Size(
        NotificationToasts.width + 2 * NotificationToasts.horizontalInset,
        200,
      ),
      data: {
        'notifications': popups.take(NotificationToasts.visibleCount).toList(),
        'onRight': widget.notifications?.toastOnRight ?? false,
        'overflow': (popups.length - NotificationToasts.visibleCount).clamp(
          0,
          popups.length,
        ),
        'scale': MediaQuery.textScalerOf(context).scale(1),
      },
      theme: widget.preferences.theme,
    );
  }

  void _applyWorkspaceCount() {
    final count = widget.system?.layout.workspaceCount;
    if (count != null) unawaited(widget.hyprland?.setWorkspaceCount(count));
  }

  bool _appliedBottom = false;

  /// Moves the native bar and its popups to the preferred output edge.
  void _applyEdge() {
    final bottom = widget.system?.bottom ?? false;
    if (bottom == _appliedBottom) return;
    _appliedBottom = bottom;
    unawaited(
      _window?.invokeMethod<void>('setBottom', bottom).catchError((
        Object error,
      ) {
        debugPrint('Bar position: $error');
      }),
    );
  }

  @override
  void dispose() {
    _fullscreenRetry?.cancel();
    _toastExit?.cancel();
    widget.notifications?.removeListener(_onNotificationsChanged);
    widget.osd?.removeListener(_syncOsd);
    widget.notifications?.releaseOutput(this);
    widget.hyprland?.removeListener(_onOutputState);
    widget.hyprland?.layoutChanges.removeListener(_onKeyboardLayout);
    widget.system?.releaseHardware(this);
    _sidebar?.dispose();
    unawaited(_keyboardDevice.close());
    widget.account?.removeListener(_updateSidebar);
    widget.preferences.removeListener(_updatePopupThemes);
    _window?.setMethodCallHandler(null);
    widget.system?.removeListener(_applyWorkspaceCount);
    widget.system?.removeListener(_applyEdge);
    _popup.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.preferences,
      builder: (context, child) => MaterialApp(
        title: "Remy'a Bar",
        debugShowCheckedModeBanner: false,
        theme: barTheme(widget.preferences.theme.theme(.light)),
        darkTheme: barTheme(widget.preferences.theme.theme(.dark)),
        themeMode: widget.preferences.theme.mode,
        home: TickerMode(enabled: !_fullscreen, child: child!),
      ),
      child: ClipRRect(
        borderRadius: .circular(20),
        child: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([
              widget.preferences,
              widget.hyprland,
              widget.system,
              widget.notifications,
              widget.aiUsage,
              widget.system?.resourcePill,
            ]),
            builder: (context, _) => BarPopupScope(
              theme: widget.preferences.theme,
              bottom: widget.system?.bottom ?? false,
              popup: _popup,
              child: BarContent(
                error: widget.preferences.error,
                hyprland: widget.hyprland,
                system: widget.system,
                weather: widget.weather,
                notifications: widget.notifications,
                aiUsage: widget.aiUsage,
                pillSnapshot: widget.system?.resourcePill.value,
                sidebarOpen: _sidebarOpen,
                notificationsOpen: _notificationsOpen,
                tray: widget.tray == null
                    ? null
                    : BarTray(key: _tray, popup: _popup, backend: widget.tray!),
                onToggleSidebar: _toggleSidebar,
                onToggleNotifications: _toggleNotifications,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
