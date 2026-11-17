import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

import 'bar_content.dart';
import 'bar_theme.dart';
import 'features/settings/bar_settings_entry.dart';
import 'features/account/account_profile_controller.dart';
import 'features/ai_usage/ai_usage_backend.dart';
import 'features/ai_usage/ai_usage_data.dart';
import 'features/sidebar/right_sidebar.dart';
import 'features/sidebar/sidebar_backend.dart';
import 'features/sidebar/sidebar_screen_capture.dart';
import 'features/notifications/notification_backend.dart';
import 'features/notifications/notification_view.dart';
import 'features/osd/osd_controller.dart';
import 'features/osd/osd_slider.dart';
import 'features/system/system_backend.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/keyboard/keyboard_device.dart';
import 'features/keyboard/keyboard_panel.dart';
import 'features/popups/bar_popup.dart';
import 'features/resources/bar_resources.dart';
import 'features/resources/resource_data.dart';
import 'features/tray/bar_tray.dart';
import 'features/workspaces/bar_workspaces.dart';

part 'app_popup_actions.dart';

Future<void> _openPowerSettings() => openRemyaSettings(page: 'power');
Future<void> _defaultLaunchScreenCapture(List<String> arguments) =>
    openRemyaScreenCapture(arguments: arguments);

class RemyaBarApp extends StatefulWidget {
  const RemyaBarApp({
    super.key,
    required this.preferences,
    this.hyprland,
    this.system,
    this.account,
    this.aiUsage,
    this.notifications,
    this.osd,
    this.onOpenSettingsPage,
    this.showTray = false,
    this.onOpenSettings = openRemyaSettings,
    this.onOpenPowerSettings = _openPowerSettings,
    this.onLaunchScreenCapture = _defaultLaunchScreenCapture,
  });

  final SettingsThemeController preferences;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final AccountProfileController? account;
  final AiUsageBackend? aiUsage;
  final NotificationBackend? notifications;
  final OsdController? osd;
  final Future<void> Function(String page)? onOpenSettingsPage;
  final bool showTray;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenPowerSettings;
  final Future<void> Function(List<String> arguments) onLaunchScreenCapture;

  @override
  State<RemyaBarApp> createState() => _RemyaBarAppState();
}

class _RemyaBarAppState extends State<RemyaBarApp> {
  final _pillSnapshot = ValueNotifier<SystemSnapshot?>(null);
  Timer? _pillRefresh;
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
  bool? _reportedFullscreen;
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
      final output = widget.hyprland!.output?.name;
      if (output != null && hidden != _reportedFullscreen) {
        _reportedFullscreen = hidden;
        await widget.notifications?.setFullscreen(output, hidden);
      }
    } catch (error) {
      debugPrint('Bar fullscreen state: $error');
    } finally {
      _checkingFullscreen = false;
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
      await BarPopup.hide(kind: 'sidebar');
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

  static const _window = MethodChannel('top.remya.bar/window');

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
    final geometry = await _window.invokeMapMethod<String, int>('output');
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
      await BarPopup.hide(kind: 'notifications');
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
      await BarPopup.show(
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
      BarPopup.update(
        kind: 'notifications',
        anchor: _popupAnchor,
        size: const Size(420, 663),
        data: _notificationsData(
          _notificationsScale,
          reservedHeight: _notificationsReservedHeight,
        ),
        theme: widget.preferences.theme,
      ).catchError(
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
      BarPopup.update(
        kind: 'sidebar',
        anchor: const Rect.fromLTWH(0, 0, 1, 1),
        size: sidebarSize,
        data: _sidebarData,
        theme: widget.preferences.theme,
      ).catchError((Object error) => debugPrint('Sidebar update: $error')),
    );
  }

  void _updatePopupThemes() {
    _updateSidebar();
    _updateNotifications();
    if (_showingOsd) unawaited(_syncOsd());
    unawaited(
      BarPopup.update(
        kind: keyboardKind,
        anchor: _popupAnchor,
        size: keyboardSize,
        data: const {},
        theme: widget.preferences.theme,
      ).catchError((Object error) => debugPrint('Keyboard theme: $error')),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.system case final system?) {
      _pillSnapshot.value = system.resourceSnapshot;
      system.hardware.addListener(_showFirstResourceSample);
      system.addListener(_applyWorkspaceCount);
      system.addListener(_applyEdge);
      _applyWorkspaceCount();
      _applyEdge();
      _pillRefresh = Timer.periodic(const Duration(seconds: 3), (_) {
        _pillSnapshot.value = system.resourceSnapshot;
      });
    }
    if (widget.hyprland case final hyprland?) {
      hyprland.addListener(_scheduleFullscreenCheck);
      hyprland.addListener(_syncOsdOutput);
      _fullscreenReconcile = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkFullscreen(),
      );
      _scheduleFullscreenCheck();
    }
    widget.account?.addListener(_updateSidebar);
    widget.notifications?.addListener(_onNotificationsChanged);
    widget.osd?.addListener(_syncOsd);
    widget.preferences.addListener(_updatePopupThemes);
    _window.setMethodCallHandler((call) async {
      if (call.method == 'outputChanged') {
        final geometry = Map<String, int>.from(call.arguments as Map);
        widget.hyprland?.updateOutput(x: geometry['x']!, y: geometry['y']!);
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

  bool _showingToasts = false;
  bool _syncingToasts = false;
  bool _toastsDirty = false;
  bool _showingOsd = false;
  bool _syncingOsd = false;
  bool _osdDirty = false;

  void _syncOsdOutput() {
    widget.osd?.updateOutput(widget.hyprland?.output?.name);
  }

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
      if (current != null &&
          current.type != .brightness &&
          widget.hyprland != null) {
        final output = widget.hyprland!.output?.name;
        if (output != null) {
          visible = await widget.hyprland!.focusedOutput() == output;
        } else {
          visible = false;
        }
      }
      if (!visible) {
        if (_showingOsd) {
          _showingOsd = false;
          await BarPopup.hide(kind: osdKind);
        }
        return;
      }
      if (!mounted) return;
      final request = _showingOsd ? BarPopup.update : BarPopup.show;
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
      final popups = backend.popups.take(4).toList();
      var host = backend.center?.popupHost;
      if (popups.isNotEmpty && host == null && output != null) {
        final active = jsonDecode(
          await widget.hyprland!.request('j/activeworkspace'),
        );
        if (active is Map &&
            active['monitor'] == output &&
            await backend.claimPopups(output)) {
          host = output;
        }
      }
      final visible =
          popups.isNotEmpty && host == output && !_notificationsOpen;
      if (!visible) {
        if (_showingToasts) {
          _showingToasts = false;
          await BarPopup.hide(kind: notificationToastsKind);
        }
        return;
      }
      if (!mounted) return;
      final request = _showingToasts ? BarPopup.update : BarPopup.show;
      _showingToasts = true;
      await request(
        kind: notificationToastsKind,
        anchor: const Rect.fromLTWH(0, 0, 1, 1),
        size: Size(
          NotificationToasts.width + NotificationToasts.insets.horizontal,
          200,
        ),
        data: {
          'notifications': [for (final item in popups) backend.toData(item)],
          'scale': MediaQuery.textScalerOf(context).scale(1),
        },
        theme: widget.preferences.theme,
      );
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
      _window.invokeMethod<void>('setBottom', bottom).catchError((
        Object error,
      ) {
        debugPrint('Bar position: $error');
      }),
    );
  }

  void _showFirstResourceSample() {
    final next = widget.system?.resourceSnapshot;
    if (!BarResources.hasData(_pillSnapshot.value) &&
        BarResources.hasData(next)) {
      _pillSnapshot.value = next;
    }
  }

  @override
  void dispose() {
    widget.notifications?.removeListener(_onNotificationsChanged);
    widget.osd?.removeListener(_syncOsd);
    widget.notifications?.dispose();
    widget.osd?.dispose();
    _fullscreenCheck?.cancel();
    _fullscreenReconcile?.cancel();
    widget.hyprland?.removeListener(_scheduleFullscreenCheck);
    widget.hyprland?.removeListener(_syncOsdOutput);
    _pillRefresh?.cancel();
    _sidebar?.dispose();
    unawaited(_keyboardDevice.close());
    widget.account?.removeListener(_updateSidebar);
    widget.account?.dispose();
    widget.preferences.removeListener(_updatePopupThemes);
    _window.setMethodCallHandler(null);
    widget.system?.hardware.removeListener(_showFirstResourceSample);
    widget.system?.removeListener(_applyWorkspaceCount);
    widget.system?.removeListener(_applyEdge);
    BarPopup.channel.setMethodCallHandler(null);
    widget.preferences.dispose();
    _pillSnapshot.dispose();
    widget.hyprland?.dispose();
    widget.system?.dispose();
    widget.aiUsage?.dispose();
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
        home: child,
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
              _pillSnapshot,
            ]),
            builder: (context, _) => BarPopupScope(
              theme: widget.preferences.theme,
              bottom: widget.system?.bottom ?? false,
              child: BarContent(
                error: widget.preferences.error,
                hyprland: widget.hyprland,
                system: widget.system,
                notifications: widget.notifications,
                aiUsage: widget.aiUsage,
                pillSnapshot: _pillSnapshot.value,
                sidebarOpen: _sidebarOpen,
                notificationsOpen: _notificationsOpen,
                tray: widget.showTray ? BarTray(key: _tray) : null,
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
