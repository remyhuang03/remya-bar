import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import 'notification_backend.dart';

/// Bell and notification count; hovering or clicking opens the center.
class BarNotifications extends StatelessWidget {
  const BarNotifications({super.key, required this.backend});

  final NotificationBackend backend;

  @override
  Widget build(BuildContext context) {
    final history = backend.history;
    final error = backend.error;
    final dnd = backend.quietReason != null;
    final count = history.length;
    return BarPill(
      padding: const .symmetric(horizontal: 12),
      semanticsLabel: error != null
          ? 'Notifications unavailable'
          : '$count notifications${dnd ? ', do not disturb' : ''}',
      card: BarPillCard(
        kind: 'notifications',
        size: const Size(420, 640),
        openOnTap: true,
        data: {
          'notifications': [for (final item in history) backend.toData(item)],
          'dnd': backend.doNotDisturb,
          'quietReason': backend.quietReason,
          'serviceError': error,
        },
      ),
      builder: (context, state) {
        final colors = Theme.of(context).colorScheme;
        return Row(
          mainAxisSize: .min,
          children: [
            Icon(
              error != null
                  ? Icons.notifications_off_rounded
                  : dnd
                  ? Icons.notifications_paused_rounded
                  : Icons.notifications_rounded,
              size: 18,
              color: state.pressed ? state.foreground : colors.onSurfaceVariant,
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
    );
  }
}
