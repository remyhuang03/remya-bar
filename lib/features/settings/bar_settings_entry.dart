import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

import '../../bar_theme.dart';
import 'bar_settings_controller.dart';
import 'bar_settings_pages.dart';
import 'bar_theme_controller.dart';

const barSettingsChannel = MethodChannel('top.remya.bar/settings');

Future<void> openBarSettings({String page = ''}) =>
    barSettingsChannel.invokeMethod<void>('open', page);

/// Pages registered in linux/packaging/remya-bar.json, in navigation order.
const barSettingsPages = [
  (id: 'layout', title: 'Layout', icon: Icons.view_agenda_rounded),
  (id: 'osd', title: 'On-screen display', icon: Icons.tune_rounded),
  (
    id: 'notifications',
    title: 'Notifications',
    icon: Icons.notifications_rounded,
  ),
  (id: 'ai-ring', title: 'AI quota rings', icon: Icons.donut_large_rounded),
];

/// The Remya Bar settings window hosted on the popup engine. [request]
/// changes on every `open`, so reopening the same page navigates again.
class BarSettingsEntry extends StatefulWidget {
  const BarSettingsEntry({
    super.key,
    required this.page,
    required this.request,
    this.controller,
  });

  final String page;
  final int request;

  /// Injected by tests; the window creates and owns its own otherwise.
  final BarSettingsController? controller;

  @override
  State<BarSettingsEntry> createState() => _BarSettingsEntryState();
}

class _BarSettingsEntryState extends State<BarSettingsEntry> {
  late final _controller = widget.controller ?? BarSettingsController();
  SettingsThemeController? _theme;
  var _index = 0;

  void _open(String page) {
    final index = barSettingsPages.indexWhere((entry) => entry.id == page);
    if (index >= 0) _index = index;
  }

  @override
  void initState() {
    super.initState();
    _open(widget.page);
    if (widget.controller == null) {
      unawaited(_controller.start());
      unawaited(_startTheme());
    }
  }

  Future<void> _startTheme() async {
    final theme = barThemeController(await barRepositoryRoot());
    if (!mounted) return theme.dispose();
    setState(() => _theme = theme);
    await theme.start();
  }

  @override
  void didUpdateWidget(BarSettingsEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request != oldWidget.request) _open(widget.page);
  }

  @override
  void dispose() {
    _theme?.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, ?_theme]),
    builder: (context, _) {
      final theme = _theme?.theme ?? const RemyaTheme();
      return MaterialApp(
        title: 'Remya Bar Settings',
        debugShowCheckedModeBanner: false,
        theme: barTheme(theme.theme(.light)),
        darkTheme: barTheme(theme.theme(.dark)),
        themeMode: theme.mode,
        home: Scaffold(
          body: Row(
            crossAxisAlignment: .stretch,
            children: [
              NavigationRail(
                selectedIndex: _index,
                labelType: .all,
                groupAlignment: -1,
                onDestinationSelected: (index) =>
                    setState(() => _index = index),
                destinations: [
                  for (final page in barSettingsPages)
                    NavigationRailDestination(
                      icon: Icon(page.icon),
                      label: Text(page.title),
                    ),
                ],
              ),
              Expanded(
                child: BarSettingsPage(
                  key: ValueKey(barSettingsPages[_index].id),
                  id: barSettingsPages[_index].id,
                  title: barSettingsPages[_index].title,
                  controller: _controller,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
