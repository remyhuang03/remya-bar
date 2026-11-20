import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:remya_ui/remya_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import 'bar_settings_controller.dart';
import 'bar_settings_pages.dart';

const barSettingsChannel = MethodChannel('top.remya.bar/settings');

Future<void> openBarSettings({String page = ''}) =>
    barSettingsChannel.invokeMethod<void>('open', page);

const _accountPage = 'account';

/// Bar preference pages in navigation order.
const barSettingsPages = [
  (
    id: 'layout',
    title: 'Layout',
    icon: Icons.view_agenda_rounded,
    category: RemyaSettingsCategory.personalization,
  ),
  (
    id: 'osd',
    title: 'On-screen display',
    icon: Icons.tune_rounded,
    category: RemyaSettingsCategory.system,
  ),
  (
    id: 'weather',
    title: 'Weather',
    icon: Icons.cloud_outlined,
    category: RemyaSettingsCategory.system,
  ),
  (
    id: 'notifications',
    title: 'Notifications',
    icon: Icons.notifications_rounded,
    category: RemyaSettingsCategory.system,
  ),
  (
    id: 'ai-ring',
    title: 'AI quota rings',
    icon: Icons.donut_large_rounded,
    category: RemyaSettingsCategory.system,
  ),
];

/// The Remya Bar settings window. [request]
/// changes on every `open`, so reopening the same page navigates again.
class BarSettingsEntry extends StatefulWidget {
  const BarSettingsEntry({
    super.key,
    required this.page,
    required this.request,
    required this.preferences,
    this.controller,
  });

  final String page;
  final int request;
  final SettingsThemeController preferences;

  /// Injected by tests; the window creates and owns its own otherwise.
  final BarSettingsController? controller;

  @override
  State<BarSettingsEntry> createState() => _BarSettingsEntryState();
}

class _BarSettingsEntryState extends State<BarSettingsEntry> {
  late final _controller = widget.controller ?? BarSettingsController();
  late final _version = remyaAppVersion();
  var _selected = barSettingsPages.first.id;

  void _open(String page) {
    if (page == remyaMaterialThemePageId ||
        page == _accountPage ||
        barSettingsPages.any((entry) => entry.id == page)) {
      _selected = page;
    }
  }

  @override
  void initState() {
    super.initState();
    _open(widget.page);
    if (widget.controller == null) {
      unawaited(_controller.start());
    }
  }

  @override
  void didUpdateWidget(BarSettingsEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request != oldWidget.request) _open(widget.page);
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _select(String id) => setState(() => _selected = id);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, widget.preferences]),
    builder: (context, _) {
      final theme = widget.preferences.theme;
      return MaterialApp(
        title: _title,
        debugShowCheckedModeBanner: false,
        theme: theme.theme(.light),
        darkTheme: theme.theme(.dark),
        themeMode: theme.mode,
        home: Column(
          children: [
            RemyaTitleBar(
              icon: SvgPicture.asset(_appIcon),
              title: _title,
              dragArea: (child) => GestureDetector(
                behavior: .opaque,
                onPanStart: (_) => barSettingsChannel.invokeMethod<void>(
                  'startMove',
                  View.of(context).viewId,
                ),
                child: child,
              ),
              onClose: () => barSettingsChannel.invokeMethod<void>(
                'close',
                View.of(context).viewId,
              ),
            ),
            Expanded(
              child: RemyaSettingsScaffold(
                selected: _selected,
                onSelected: _select,
                loading: barSettingsPageLoading(_controller, _selected),
                pages: [
                  for (final page in barSettingsPages)
                    RemyaSettingsPage(
                      id: page.id,
                      title: page.title,
                      icon: page.icon,
                      category: page.category,
                      builder: (context) =>
                          BarSettingsPage(id: page.id, controller: _controller),
                    ),
                  remyaMaterialThemePage(client: _controller.client),
                  RemyaSettingsPage(
                    id: _accountPage,
                    title: 'Account',
                    icon: Icons.person_outline_rounded,
                    category: .privacy,
                    builder: (context) => RemyaAvatarEditor(
                      client: _controller.client,
                      pickImage: () => barSettingsChannel.invokeMethod<String>(
                        'pickAvatar',
                        View.of(context).viewId,
                      ),
                    ),
                  ),
                ],
                footerPages: [
                  RemyaSettingsPage(
                    id: 'about',
                    title: 'About',
                    icon: Icons.info_outline_rounded,
                    tabs: false,
                    children: [
                      RemyaSettingsPage(
                        id: 'about',
                        title: 'About',
                        icon: Icons.info_outline_rounded,
                        builder: (context) => _About(
                          version: _version,
                          onLicenses: () => _select('licenses'),
                        ),
                      ),
                      RemyaSettingsPage(
                        id: 'licenses',
                        title: 'Licenses',
                        icon: Icons.description_outlined,
                        fill: true,
                        builder: (context) => const RemyaLicensesView(),
                      ),
                    ],
                  ),
                ],
                onBack: _selected == 'licenses' ? () => _select('about') : null,
              ),
            ),
          ],
        ),
      );
    },
  );
}

const _title = "Remy'a Bar Settings";
const _appIcon = 'assets/icons/app_icon.svg';

class _About extends StatelessWidget {
  const _About({required this.version, required this.onLicenses});

  final Future<String?> version;
  final VoidCallback onLicenses;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      FutureBuilder(
        future: version,
        builder: (context, snapshot) => RemyaAboutHeader(
          icon: SvgPicture.asset(
            _appIcon,
            semanticsLabel: "Remy'a Bar application icon",
          ),
          name: "Remy'a Bar",
          version: snapshot.data,
        ),
      ),
      RemyaAboutLinks(
        repository: 'https://github.com/remyhuang03/remya-bar',
        onLicenses: onLicenses,
      ),
    ],
  );
}
