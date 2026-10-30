import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'features/hyprland/hyprland_backend.dart';
import 'features/settings/settings_button.dart';
import 'widgets/bar_tooltip.dart';
import 'features/popups/bar_popup.dart';

class RemyaBarApp extends StatefulWidget {
  const RemyaBarApp({
    super.key,
    required this.preferences,
    this.hyprland,
    this.onOpenSettings = openRemyaSettings,
  });

  final SettingsThemeController preferences;
  final HyprlandBackend? hyprland;
  final Future<void> Function() onOpenSettings;

  @override
  State<RemyaBarApp> createState() => _RemyaBarAppState();
}

class _RemyaBarAppState extends State<RemyaBarApp> {
  @override
  void dispose() {
    widget.preferences.dispose();
    widget.hyprland?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.preferences,
      builder: (context, _) => BarPopupScope(
        theme: widget.preferences.theme,
        child: MaterialApp(
          title: "Remy'a Bar",
          debugShowCheckedModeBanner: false,
          theme: widget.preferences.theme.theme(.light),
          darkTheme: widget.preferences.theme.theme(.dark),
          themeMode: widget.preferences.theme.mode,
          home: ClipRRect(
            borderRadius: .circular(20),
            child: Scaffold(
              body: _BarContent(
                error: widget.preferences.error,
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
  const _BarContent({required this.error, required this.onOpenSettings});

  final String? error;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Layer-shell may configure a temporary 1-pixel width during startup.
      if (constraints.maxWidth < 40) return const SizedBox.shrink();
      return Row(
        mainAxisAlignment: .end,
        children: [
          if (error != null && constraints.maxWidth >= 60)
            BarTooltip(
              message: 'Theme unavailable',
              child: const Icon(Icons.warning_amber_rounded, size: 20),
            ),
          SettingsButton(onOpen: onOpenSettings),
        ],
      );
    },
  );
}
