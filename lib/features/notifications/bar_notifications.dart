import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import '../../widgets/bar_tooltip.dart';
import 'notification_backend.dart';

/// Bell and notification count; clicking opens the notification panel.
class BarNotifications extends StatefulWidget {
  const BarNotifications({
    super.key,
    required this.backend,
    required this.onToggle,
    this.open = false,
  });

  final NotificationBackend backend;
  final Future<void> Function(Rect anchor, double scale) onToggle;
  final bool open;

  @override
  State<BarNotifications> createState() => _BarNotificationsState();
}

class _BarNotificationsState extends State<BarNotifications> {
  final _pill = GlobalKey();

  void _toggle() {
    final box = _pill.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    unawaited(
      widget.onToggle(
        box.localToGlobal(.zero) & box.size,
        MediaQuery.textScalerOf(context).scale(1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.backend.history;
    final error = widget.backend.error;
    final dnd = widget.backend.quietReason != null;
    final count = history.length;
    return BarTooltip(
      message: 'Notifications',
      child: BarPill(
        pillKey: _pill,
        padding: const .symmetric(horizontal: 12),
        toggled: widget.open,
        onTap: _toggle,
        semanticsLabel: error != null
            ? 'Notifications unavailable'
            : '$count notifications${dnd ? ', do not disturb' : ''}',
        builder: (context, state) {
          final colors = Theme.of(context).colorScheme;
          return Row(
            mainAxisSize: .min,
            spacing: count > 0 ? 4 : 0,
            children: [
              Icon(
                error != null
                    ? Icons.notifications_off_rounded
                    : dnd
                    ? Icons.notifications_paused_rounded
                    : Icons.notifications_rounded,
                size: 18,
                color: state.pressed
                    ? state.foreground
                    : colors.onSurfaceVariant,
              ),
              if (error == null && count > 0)
                Text(
                  count > 99 ? '99+' : '$count',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    height: 1.25,
                    color: state.pressed ? state.foreground : colors.primary,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
