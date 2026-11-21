import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

import '../../bar_content.dart';
import '../../bar_theme.dart';
import '../ai_usage/ai_usage_backend.dart';
import '../clock/bar_clock.dart';
import '../hyprland/hyprland_backend.dart';
import '../notifications/notification_backend.dart';
import '../popups/bar_popup.dart';
import '../sidebar/right_sidebar.dart';
import '../system/system_backend.dart';
import '../tray/bar_tray.dart';
import '../tray/tray_backend.dart';
import '../weather/weather_controller.dart';
import 'bar_preference_models.dart';

const barPillNames = {
  'notifications': 'Notifications',
  'window': 'Active window',
  'resources': 'System resources',
  'media': 'Media',
  'workspaces': 'Workspaces',
  'clock': 'Clock',
  'weather': 'Weather',
  'tray': 'App tray',
  'ai-usage': 'AI Usage',
  'battery': 'Battery',
  'sidebar': 'Quick settings',
};

const _pillIcons = {
  'notifications': Icons.notifications_rounded,
  'window': Icons.web_asset_rounded,
  'resources': Icons.memory_rounded,
  'media': Icons.music_note_rounded,
  'workspaces': Icons.space_dashboard_rounded,
  'clock': Icons.schedule_rounded,
  'weather': Icons.cloud_outlined,
  'tray': Icons.apps_rounded,
  'ai-usage': Icons.auto_awesome_rounded,
  'battery': Icons.battery_std_rounded,
  'sidebar': Icons.tune_rounded,
};

/// Shown for a pill that currently has nothing to display.
const _idleLabels = {
  'window': 'No window',
  'resources': 'No data',
  'media': 'Not playing',
  'workspaces': 'Unavailable',
  'tray': 'No apps',
  'ai-usage': 'No providers',
  'battery': 'No battery',
};

/// The application's running services, so settings can draw real pills with
/// live data instead of illustrations.
class BarLiveServices extends InheritedWidget {
  const BarLiveServices({
    super.key,
    required this.theme,
    required this.hyprland,
    required this.system,
    required this.weather,
    required this.notifications,
    required this.aiUsage,
    required this.tray,
    required super.child,
  });

  final SettingsThemeController theme;
  final HyprlandStore hyprland;
  final SystemBackend system;
  final WeatherController weather;
  final NotificationBackend notifications;
  final AiUsageBackend aiUsage;
  final TrayBackend tray;

  static BarLiveServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarLiveServices>();

  @override
  bool updateShouldNotify(BarLiveServices oldWidget) =>
      theme != oldWidget.theme ||
      hyprland != oldWidget.hyprland ||
      system != oldWidget.system;
}

/// Builds live pills for [builder] while mounted, projecting Hyprland state
/// onto the focused output. Without [BarLiveServices] pills are null.
class BarLivePills extends StatefulWidget {
  const BarLivePills({super.key, required this.builder});

  final Widget Function(BuildContext context, BarLiveBuilder? live) builder;

  @override
  State<BarLivePills> createState() => _BarLivePillsState();
}

/// Renders live bar content for a layout that may not be saved yet.
class BarLiveBuilder {
  const BarLiveBuilder._(this._state);
  final _BarLivePillsState _state;

  /// The pill [id] as the bar draws it, or null when it has nothing to show.
  Widget? pill(BuildContext context, String id, BarLayout layout) =>
      _state._pills(layout).build(context, id, layout: layout, compact: false);
}

class _BarLivePillsState extends State<BarLivePills> {
  BarLiveServices? _services;
  HyprlandBackend? _hyprland;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = BarLiveServices.maybeOf(context);
    if (services?.hyprland == _services?.hyprland) {
      _services = services;
      return;
    }
    _services = services;
    _hyprland?.dispose();
    _hyprland = null;
    if (services != null) unawaited(_project(services));
  }

  // Settings sits on some output; its workspaces are the familiar ones.
  Future<void> _project(BarLiveServices services) async {
    String? output;
    try {
      output = await services.hyprland.focusedOutput();
    } catch (error) {
      debugPrint('Settings preview output: $error');
    }
    if (!mounted || _services != services) return;
    setState(() {
      _hyprland = HyprlandBackend(store: services.hyprland, outputName: output);
    });
  }

  @override
  void dispose() {
    _hyprland?.dispose();
    super.dispose();
  }

  static Future<void> _noToggle(Rect _, double _) async {}

  Widget _sidebar(SystemBackend system) => BarSidebarButton(
    onToggle: _noToggle,
    wifi: system.quickStatus.wifi,
    bluetooth: system.quickStatus.bluetooth,
    volume: (system.mediaOutput['percent'] as num?)?.toDouble(),
    muted: system.mediaOutput['muted'] as bool?,
  );

  BarPills _pills(BarLayout layout) {
    final services = _services!;
    return BarPills(
      hyprland: _hyprland,
      system: services.system,
      weather: services.weather,
      notifications: services.notifications,
      aiUsage: services.aiUsage,
      tray: BarTray(backend: services.tray),
      pillSnapshot: services.system.resourcePill.value,
      onToggleNotifications: _noToggle,
      sidebar: _sidebar(services.system),
      clock: BarClock(showSeconds: services.system.showClockSeconds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null) return widget.builder(context, null);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.theme,
        services.system,
        services.system.resourcePill,
        services.notifications,
        services.aiUsage,
        services.weather,
        _hyprland,
      ]),
      builder: (context, _) => BarPopupScope(
        theme: services.theme.theme,
        bottom: services.system.bottom,
        // Previews never react to the pointer: no cards, menus or actions.
        child: widget.builder(context, BarLiveBuilder._(this)),
      ),
    );
  }
}

/// Applies the bar's typography and colors to a live pill outside the bar.
class BarLiveTheme extends StatelessWidget {
  const BarLiveTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: barTheme(Theme.of(context)),
    child: IgnorePointer(child: ExcludeSemantics(child: child)),
  );
}

/// The real pill [id], or a labelled placeholder when it has nothing to show.
class BarLivePill extends StatelessWidget {
  const BarLivePill({
    super.key,
    required this.id,
    required this.layout,
    required this.live,
  });

  final String id;
  final BarLayout layout;
  final BarLiveBuilder? live;

  @override
  Widget build(BuildContext context) {
    final pill = live?.pill(context, id, layout);
    if (pill != null) {
      return BarLiveTheme(
        child: SizedBox(height: 40, child: Center(widthFactor: 1, child: pill)),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 40,
      child: Center(
        widthFactor: 1,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: colors.outline)),
          ),
          child: Padding(
            padding: const .symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                Icon(_pillIcons[id], size: 16, color: colors.onSurfaceVariant),
                Text(barPillNames[id]!, style: text.labelMedium),
                if (_idleLabels[id] case final idle? when live != null)
                  Text(
                    idle,
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
