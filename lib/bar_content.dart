import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';

import 'features/ai_usage/ai_usage_backend.dart';
import 'features/ai_usage/ai_usage_data.dart';
import 'features/ai_usage/bar_ai_quota.dart';
import 'features/sidebar/right_sidebar.dart';
import 'features/battery/bar_battery.dart';
import 'features/media/bar_media.dart';
import 'features/notifications/bar_notifications.dart';
import 'features/notifications/notification_backend.dart';
import 'features/system/system_backend.dart';
import 'features/clock/bar_clock.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/resources/bar_resources.dart';
import 'features/window/bar_active_window.dart';
import 'features/weather/bar_weather.dart';
import 'features/weather/weather_controller.dart';
import 'features/workspaces/bar_workspaces.dart';
import 'widgets/bar_groups_layout.dart';
import 'widgets/bar_pill_slot.dart';
import 'widgets/bar_tooltip.dart';

/// The pill groups of one bar, laid out for its output width.
class BarContent extends StatelessWidget {
  const BarContent({
    super.key,
    required this.error,
    required this.onToggleSidebar,
    required this.onToggleNotifications,
    required this.pillSnapshot,
    required this.sidebarOpen,
    required this.notificationsOpen,
    this.hyprland,
    this.system,
    this.weather,
    this.notifications,
    this.aiUsage,
    this.tray,
  });

  final String? error;
  final SystemSnapshot? pillSnapshot;
  final HyprlandBackend? hyprland;
  final SystemBackend? system;
  final WeatherController? weather;
  final NotificationBackend? notifications;
  final AiUsageBackend? aiUsage;
  final Widget? tray;
  final bool sidebarOpen;
  final bool notificationsOpen;
  final Future<void> Function(Rect, double) onToggleSidebar;
  final Future<void> Function(Rect, double) onToggleNotifications;

  @override
  Widget build(BuildContext context) => weather == null
      ? _buildContent(context, false)
      : ValueListenableBuilder(
          valueListenable: weather!.visibility,
          builder: (context, visible, _) => _buildContent(context, visible),
        );

  Widget _buildContent(BuildContext context, bool weatherVisible) =>
      LayoutBuilder(
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
                when hyprland?.currentWindow != null &&
                    hyprland!.error == null =>
              SizedBox(
                width: BarActiveWindow.width,
                child: BarActiveWindow(
                  backend: hyprland,
                  showAppName: layout.windowAppName,
                ),
              ),
            'resources'
                when BarResources.hasData(pillSnapshot, metrics: metrics) =>
              SizedBox(
                width: BarResources.widthFor(
                  context,
                  compact: compactResources,
                  snapshot: pillSnapshot,
                  metrics: metrics,
                ),
                child: BarResources(
                  snapshot: pillSnapshot,
                  cardSnapshot: system?.hardware,
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
            'weather' when weatherVisible => BarWeather(weather: weather!),
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
            'battery' when system?.battery?.percent?.isFinite == true =>
              ValueListenableBuilder(
                valueListenable: system!.hardware,
                builder: (context, sample, _) => BarBattery(
                  battery: sample?.batteries.firstOrNull,
                  isPowerSaver: system!.isPowerSaver,
                  power: system!.batteryPower,
                ),
              ),
            'sidebar' => sidebar,
            _ => null,
          };
          // Groups and slots stay mounted so hidden pills can animate out; a
          // group's presence fades its spacing in step with its pills.
          Widget group(List<String> ids) {
            final pills = [...ids.map(pill)];
            return TweenAnimationBuilder<double>(
              tween: Tween(end: pills.any((p) => p != null) ? 1 : 0),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : BarPillSlot.duration,
              curve: BarPillSlot.curve,
              builder: (context, presence, child) =>
                  BarGroupPresence(presence: presence, child: child!),
              child: Row(
                mainAxisSize: .min,
                children: [
                  for (final (i, child) in pills.indexed)
                    BarPillSlot(
                      key: ValueKey(ids[i]),
                      leading: pills.take(i).any((p) => p != null),
                      child: child,
                    ),
                ],
              ),
            );
          }

          final groups = [...layout.groups.map(group)];
          final center = layout.center;
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
