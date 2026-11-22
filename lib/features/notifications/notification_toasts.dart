import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_flow.dart';
import 'notification_tile.dart';

const notificationToastsKind = 'notification-toasts';

/// Heads-up notifications for the output that owns the current stack.
class NotificationToasts extends StatefulWidget {
  const NotificationToasts({
    super.key,
    required this.data,
    required this.onAction,
    this.bottom = false,
  });

  static const width = 372.0;
  static const horizontalInset = 16.0;
  static const visibleCount = 3;

  final Map<String, Object?> data;
  final NotificationAction onAction;
  final bool bottom;

  @override
  State<NotificationToasts> createState() => _NotificationToastsState();
}

class _NotificationToastsState extends State<NotificationToasts> {
  final _expanded = <Object?, bool>{};
  final _announced = <Object?, Object?>{};
  bool _hovered = false;
  bool _focused = false;

  void _updatePause({bool? hovered, bool? focused}) {
    final wasPaused = _hovered || _focused;
    _hovered = hovered ?? _hovered;
    _focused = focused ?? _focused;
    final paused = _hovered || _focused;
    if (paused != wasPaused) {
      widget.onAction({'action': 'notifications.hover', 'value': paused});
    }
  }

  void _announce(Iterable<Map> items, Set<Object?> ids) {
    _announced.removeWhere((id, _) => !ids.contains(id));
    if (!MediaQuery.supportsAnnounceOf(context)) return;
    for (final item in items) {
      final id = item['id'];
      final title = item['summary'];
      if (_announced.containsKey(id) && _announced[id] == title) continue;
      _announced[id] = title;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_announced.containsKey(id) ||
            _announced[id] != title) {
          return;
        }
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            notificationAccessibleName(context, item),
            Directionality.of(context),
            assertiveness: item['urgency'] == 2 ? .assertive : .polite,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.data['notifications'] as List? ?? const [])
        .whereType<Map>();
    final ids = items.map((item) => item['id']).toSet();
    _expanded.removeWhere((id, _) => !ids.contains(id));
    _announce(items, ids);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final remaining = widget.data['overflow'] as int? ?? 0;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => _updatePause(focused: value),
      child: MouseRegion(
        onEnter: (_) => _updatePause(hovered: true),
        onExit: (_) => _updatePause(hovered: false),
        child: Padding(
          padding: .fromLTRB(
            NotificationToasts.horizontalInset,
            widget.bottom ? 24 : 0,
            NotificationToasts.horizontalInset,
            widget.bottom ? 0 : 24,
          ),
          child: NotificationFlow(
            spacing: 8,
            children: [
              for (final item in items)
                TweenAnimationBuilder<double>(
                  key: ValueKey(item['id']),
                  duration: const Duration(milliseconds: 350),
                  curve: Easing.emphasizedDecelerate,
                  tween: Tween(begin: 0, end: 1),
                  builder: (context, progress, child) => Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        reduceMotion
                            ? 0
                            : (1 - progress) * (widget.bottom ? 16 : -16),
                      ),
                      child: child,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: .all(.circular(28)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x52000000),
                          offset: Offset(0, 8),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: NotificationTile(
                      data: item,
                      expanded:
                          _expanded[item['id']] ??
                          (item['actions'] as List? ?? const []).isNotEmpty,
                      onToggle: () => setState(
                        () => _expanded[item['id']] =
                            !(_expanded[item['id']] ??
                                (item['actions'] as List? ?? const [])
                                    .isNotEmpty),
                      ),
                      onAction: widget.onAction,
                      toast: true,
                    ),
                  ),
                ),
              if (remaining > 0)
                Align(
                  key: const ValueKey('overflow'),
                  alignment: .centerRight,
                  child: FilledButton.tonal(
                    onPressed: () =>
                        widget.onAction(const {'action': 'notification.open'}),
                    style: FilledButton.styleFrom(
                      textStyle: Theme.of(context).textTheme.labelMedium,
                      visualDensity: .compact,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: .shrinkWrap,
                    ),
                    child: Text('+$remaining more · Open notifications'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
