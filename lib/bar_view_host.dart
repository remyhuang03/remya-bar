import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

import 'features/popups/bar_popup.dart';
import 'features/popups/popup_app.dart';
import 'features/settings/bar_settings_entry.dart';

const barViewsChannel = MethodChannel('top.remya.bar/views');

/// Mounts each native view once its role and Flutter surface are known.
class BarViewHost extends StatefulWidget {
  const BarViewHost({
    super.key,
    required this.preferences,
    required this.buildBar,
  });

  final SettingsThemeController preferences;
  final Widget Function(int viewId) buildBar;

  @override
  State<BarViewHost> createState() => _BarViewHostState();
}

enum _ViewRole { bar, popup, settings }

class _BarViewHostState extends State<BarViewHost> with WidgetsBindingObserver {
  List<FlutterView> _views = const [];
  Map<int, _ViewRole> _roles = const {};
  int _revision = -1;
  int _settingsRequest = 0;
  ({int id, String page})? _settings;

  List<FlutterView> _platformViews() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    return [
      for (final view in dispatcher.views)
        if (view.viewId != dispatcher.implicitView?.viewId) view,
    ];
  }

  void _applySnapshot(Object? snapshot) {
    if (!mounted) return;
    if (snapshot is! Map ||
        snapshot['revision'] is! int ||
        snapshot['views'] is! Map) {
      throw const FormatException('Invalid bar view registry snapshot');
    }
    final revision = snapshot['revision'] as int;
    // A complete change can arrive before the earlier list response.
    if (revision <= _revision) return;
    final roles = <int, _ViewRole>{};
    for (final entry in (snapshot['views'] as Map).entries) {
      final id = entry.key is String ? int.tryParse(entry.key as String) : null;
      final role = switch (entry.value) {
        'bar' => _ViewRole.bar,
        'popup' => _ViewRole.popup,
        'settings' => _ViewRole.settings,
        _ => null,
      };
      if (id != null && role != null) roles[id] = role;
    }
    setState(() {
      _revision = revision;
      _roles = roles;
    });
  }

  Future<void> _listViews() async {
    try {
      _applySnapshot(await barViewsChannel.invokeMethod<Object?>('list'));
    } catch (error) {
      if (mounted) debugPrint('Bar view registry: $error');
    }
  }

  Future<void> _settingsReady() async {
    try {
      await barSettingsChannel.invokeMethod<void>('ready');
    } catch (error) {
      if (mounted) debugPrint('Bar settings window: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _views = _platformViews();
    barViewsChannel.setMethodCallHandler((call) async {
      if (call.method != 'changed') throw MissingPluginException();
      _applySnapshot(call.arguments);
    });
    barSettingsChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      final args = call.arguments;
      switch (call.method) {
        case 'open':
          if (args is! Map ||
              args['viewId'] is! int ||
              args['page'] is! String) {
            throw const FormatException('Invalid settings view');
          }
          setState(() {
            _settings = (
              id: args['viewId'] as int,
              page: args['page'] as String,
            );
            _settingsRequest++;
          });
        case 'closed':
          if (_settings?.id == args) setState(() => _settings = null);
        default:
          throw MissingPluginException();
      }
    });
    unawaited(_listViews());
    unawaited(_settingsReady());
  }

  @override
  void didChangeMetrics() {
    final views = _platformViews();
    if (!listEquals(_views, views)) setState(() => _views = views);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    barSettingsChannel.setMethodCallHandler(null);
    barViewsChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Widget _buildView(int viewId, _ViewRole role) => switch (role) {
    .bar => widget.buildBar(viewId),
    .popup => BarPopupApp(channel: BarPopup.viewChannel(viewId)),
    .settings => BarSettingsEntry(
      page: _settings?.id == viewId ? _settings!.page : '',
      request: _settingsRequest,
      preferences: widget.preferences,
    ),
  };

  @override
  Widget build(BuildContext context) => ViewCollection(
    views: [
      for (final view in _views)
        if (_roles[view.viewId] case final role?)
          View(
            key: ValueKey(view.viewId),
            view: view,
            child: _buildView(view.viewId, role),
          ),
    ],
  );
}
