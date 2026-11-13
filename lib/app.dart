import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_ui/remya_ui.dart';

import 'bar_theme.dart';
import 'features/settings/bar_settings_entry.dart';
import 'features/account/account_profile_controller.dart';
import 'features/ai_usage/ai_usage_backend.dart';
import 'features/ai_usage/ai_usage_data.dart';
import 'features/ai_usage/bar_ai_quota.dart';
import 'features/sidebar/right_sidebar.dart';
import 'features/sidebar/sidebar_backend.dart';
import 'features/sidebar/sidebar_screen_capture.dart';
import 'features/battery/bar_battery.dart';
import 'features/media/bar_media.dart';
import 'features/notifications/bar_notifications.dart';
import 'features/notifications/notification_backend.dart';
import 'features/notifications/notification_view.dart';
import 'features/osd/osd_controller.dart';
import 'features/osd/osd_slider.dart';
import 'features/system/system_backend.dart';
import 'features/clock/bar_clock.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/keyboard/keyboard_device.dart';
import 'features/keyboard/keyboard_panel.dart';
import 'features/popups/bar_popup.dart';
import 'features/resources/bar_resources.dart';
import 'features/resources/resource_data.dart';
import 'features/tray/bar_tray.dart';
import 'features/window/bar_active_window.dart';
import 'features/workspaces/bar_workspaces.dart';
import 'widgets/bar_groups_layout.dart';
import 'widgets/bar_tooltip.dart';

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
  SystemSnapshot? _pillSnapshot;
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

  void _showFirstResourceSample() {
    final next = widget.system?.resourceSnapshot;
    if (!BarResources.hasData(_pillSnapshot) && BarResources.hasData(next)) {
      setState(() => _pillSnapshot = next);
    }
  }

  Future<Object?> _popupAction(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final args = call.arguments;
    if (args is! Map) throw const FormatException('Invalid popup action');
    final action = args['action'];
    if (action == 'card.state') {
      final kind = args['kind'];
      final open = args['open'];
      if (kind is! String ||
          !const {
            'media',
            'battery',
            'datetime',
            'resources',
            aiUsageKind,
          }.contains(kind) ||
          open is! bool) {
        throw const FormatException('Invalid card state');
      }
      if (open) {
        BarPopup.openCard.value = kind;
      } else if (BarPopup.openCard.value == kind) {
        BarPopup.openCard.value = null;
      }
    } else if (action == 'keyboard.visibility' && args['open'] is bool) {
      BarPopup.keyboardOpen.value = args['open'] as bool;
    } else if (action == 'sidebar.closed') {
      _sidebarOpen = false;
      _sidebar?.close();
    } else if (action == 'notifications.closed') {
      _notificationsOpen = false;
      unawaited(_syncToasts());
    } else if (action == 'sidebar.capture') {
      final arguments = switch (args['target']) {
        'screenshot' => const <String>[],
        'record' => const ['--record'],
        'picker' => const ['--color-picker'],
        _ => throw const FormatException('Invalid capture target'),
      };
      await widget.onLaunchScreenCapture(arguments);
      await BarPopup.hide(kind: 'sidebar');
      _sidebarOpen = false;
      _sidebar?.close();
    } else if (action == 'sidebar.keyboard' && args['value'] is bool) {
      if (!_sidebarOpen) throw StateError('Sidebar is closed');
      if (args['value'] == false) {
        await BarPopup.hide(kind: keyboardKind);
        _updateSidebar();
      } else {
        final backend = widget.hyprland;
        if (backend == null) throw StateError('Hyprland is unavailable');
        final device = await _keyboardDevice.read(backend);
        if (!mounted || !_sidebarOpen) return null;
        final focus = _sidebarFocus;
        await BarPopup.show(
          kind: keyboardKind,
          anchor: _popupAnchor,
          size: keyboardSize,
          data: {'device': device},
          theme: widget.preferences.theme,
        );
        if (focus != null) {
          try {
            await backend.request(
              'dispatch hl.dsp.focus({ window = "address:$focus" })',
            );
          } catch (error) {
            debugPrint('Keyboard focus restore: $error');
          }
        }
      }
    } else if (action == 'keyboard.device' || action == 'keyboard.cursor') {
      final backend = widget.hyprland;
      if (backend == null) throw StateError('Hyprland is unavailable');
      return action == 'keyboard.cursor'
          ? jsonDecode(await backend.request('j/cursorpos'))
          : _keyboardDevice.read(backend, select: args['value'] as int?);
    } else if (action == 'keyboard.settings') {
      await openBarSettings(page: 'layout');
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
      if (page == 'remya-bar') {
        await openBarSettings();
      } else {
        await (widget.onOpenSettingsPage ??
            (page) => openRemyaSettings(page: page))(page);
      }
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
    } else if (action is String &&
        (action.startsWith('notification.') ||
            action == 'notifications.hover')) {
      await _notificationAction(action, args);
    } else if (action is String && action.startsWith('tray.')) {
      await _tray.currentState?.popupAction(args);
    } else if (action == 'ai-usage.refresh' &&
        BarPopup.openCard.value == aiUsageKind) {
      await widget.aiUsage?.refresh();
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
    return null;
  }

  Future<void> _notificationAction(String action, Map args) async {
    final backend = widget.notifications;
    if (backend == null) throw StateError('Notifications unavailable');
    final id = args['id'];
    final value = args['value'];
    switch (action) {
      case 'notification.dismiss' when id is int:
        await backend.dismiss(id);
      case 'notification.clear':
        await backend.dismiss(null);
      case 'notification.invoke' when id is int && args['key'] is String:
        await backend.invoke(id, args['key'] as String);
      case 'notification.dnd' when value is bool:
        await backend.setDoNotDisturb(value);
      case 'notification.link' when args['href'] is String:
        await openNotificationLink(args['href'] as String);
      case 'notifications.hover' when value is bool:
        await backend.hover(value);
      default:
        throw const FormatException('Invalid notification action');
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
    widget.system?.removeListener(_showFirstResourceSample);
    widget.system?.removeListener(_applyWorkspaceCount);
    BarPopup.channel.setMethodCallHandler(null);
    widget.preferences.dispose();
    widget.hyprland?.dispose();
    widget.system?.dispose();
    widget.aiUsage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.preferences,
        widget.hyprland,
        widget.system,
        widget.notifications,
        widget.aiUsage,
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
                notifications: widget.notifications,
                aiUsage: widget.aiUsage,
                pillSnapshot: _pillSnapshot,
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

class _BarContent extends StatelessWidget {
  const _BarContent({
    required this.error,
    required this.onToggleSidebar,
    required this.onToggleNotifications,
    required this.pillSnapshot,
    required this.sidebarOpen,
    required this.notificationsOpen,
    this.hyprland,
    this.system,
    this.notifications,
    this.aiUsage,
    this.tray,
  });

  final String? error;
  final SystemSnapshot? pillSnapshot;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final NotificationBackend? notifications;
  final AiUsageBackend? aiUsage;
  final Widget? tray;
  final bool sidebarOpen;
  final bool notificationsOpen;
  final Future<void> Function(Rect, double) onToggleSidebar;
  final Future<void> Function(Rect, double) onToggleNotifications;

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
        // Keep title changes from resizing the pill; omit empty workspaces.
        'window'
            when hyprland?.currentWindow != null && hyprland!.error == null =>
          SizedBox(
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
                    marquee: layout.mediaMarquee,
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
        'clock' => clock,
        'notifications' when notifications != null => BarNotifications(
          backend: notifications!,
          onToggle: onToggleNotifications,
          open: notificationsOpen,
        ),
        'tray' when tray != null => ConstrainedBox(
          constraints: const .new(maxWidth: 290),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < 44 ? const SizedBox.shrink() : tray!,
          ),
        ),
        aiUsageKind when aiUsage?.visible == true => BarAiQuota(
          backend: aiUsage!,
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
