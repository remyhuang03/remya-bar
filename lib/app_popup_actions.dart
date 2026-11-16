part of 'app.dart';

/// Requests from popup views, dispatched to the bar's backends.
extension _PopupActions on _RemyaBarAppState {
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
          anchor: _RemyaBarAppState._popupAnchor,
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
}
