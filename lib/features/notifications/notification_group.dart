import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_flow.dart';
import 'notification_tile.dart';

class NotificationGroup extends StatefulWidget {
  const NotificationGroup({
    super.key,
    required this.items,
    required this.expanded,
    required this.radius,
    required this.focusNode,
    required this.showFocusIndicator,
    required this.traversable,
    required this.onFocusChange,
    required this.onToggle,
    required this.onDismiss,
    required this.onDismissSection,
    required this.children,
  });

  final List<Map> items;
  final bool expanded;
  final BorderRadius radius;
  final FocusNode focusNode;
  final bool showFocusIndicator;
  final bool traversable;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onToggle;
  final VoidCallback? onDismiss;
  final VoidCallback onDismissSection;
  final List<Widget> children;

  @override
  State<NotificationGroup> createState() => _NotificationGroupState();
}

class _NotificationGroupState extends State<NotificationGroup> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final latest = widget.items.first;
    final app = latest['appName'] as String?;
    final name = app == null || app.isEmpty ? 'Notifications' : app;
    final meta = theme.textTheme.bodySmall?.copyWith(
      height: 16 / 12,
      color: colors.onSurfaceVariant,
    );
    final critical = latest['urgency'] == 2;
    final background = critical
        ? Color.alphaBlend(
            colors.error.withValues(alpha: .08),
            colors.surfaceContainerHighest,
          )
        : colors.surfaceContainerHighest;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      decoration: BoxDecoration(color: background, borderRadius: widget.radius),
      clipBehavior: .antiAlias,
      child: Material(
        type: .transparency,
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Easing.emphasizedDecelerate,
          alignment: .topCenter,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              FocusTraversalGroup(
                descendantsAreTraversable: widget.traversable,
                child: CallbackShortcuts(
                  bindings: {
                    if (widget.onToggle case final toggle?) ...{
                      const SingleActivator(LogicalKeyboardKey.enter): toggle,
                      const SingleActivator(LogicalKeyboardKey.space): toggle,
                      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                        if (!widget.expanded) toggle();
                      },
                      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                        if (widget.expanded) toggle();
                      },
                    },
                    if (widget.onDismiss case final dismiss?) ...{
                      const SingleActivator(LogicalKeyboardKey.delete): dismiss,
                      const SingleActivator(LogicalKeyboardKey.backspace):
                          dismiss,
                    },
                    const SingleActivator(
                      LogicalKeyboardKey.delete,
                      shift: true,
                    ): widget.onDismissSection,
                  },
                  child: FocusableActionDetector(
                    focusNode: widget.focusNode,
                    onFocusChange: (focused) {
                      setState(() => _focused = focused);
                      widget.onFocusChange(focused);
                    },
                    mouseCursor: widget.onToggle == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hovered = true),
                      onExit: (_) => setState(() => _hovered = false),
                      child: GestureDetector(
                        behavior: .opaque,
                        onTap: widget.onToggle,
                        onTertiaryTapUp: widget.onDismiss == null
                            ? null
                            : (_) => widget.onDismiss!(),
                        child: DecoratedBox(
                          position: .foreground,
                          decoration: BoxDecoration(
                            color: _hovered
                                ? colors.onSurface.withValues(alpha: .08)
                                : null,
                            borderRadius: widget.radius,
                            border: widget.showFocusIndicator && _focused
                                ? Border.all(color: colors.secondary, width: 3)
                                : null,
                          ),
                          child: Padding(
                            padding: .fromLTRB(
                              16,
                              16,
                              16,
                              widget.expanded ? 16 : 4,
                            ),
                            child: Row(
                              spacing: 16,
                              children: [
                                NotificationLeading(
                                  data: {...latest, 'avatar': false},
                                  background: background,
                                ),
                                Expanded(
                                  child: Row(
                                    spacing: 4,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: .ellipsis,
                                          style: meta?.copyWith(
                                            fontWeight: .w500,
                                          ),
                                        ),
                                      ),
                                      Text('·', style: meta),
                                      NotificationTime(
                                        received: latest['received'],
                                        style: meta,
                                      ),
                                    ],
                                  ),
                                ),
                                NotificationRowControls(
                                  expanded: widget.expanded,
                                  onToggle: widget.onToggle,
                                  onDismiss: widget.onDismiss ?? () {},
                                  showDismiss:
                                      widget.onDismiss != null &&
                                      (_hovered ||
                                          (_focused &&
                                              widget.showFocusIndicator)),
                                  count: widget.items.length,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.expanded)
                NotificationFlow(
                  spacing: 0,
                  children: [
                    for (final child in widget.children)
                      Column(
                        key: child.key,
                        crossAxisAlignment: .stretch,
                        children: [
                          const Divider(height: 1, indent: 72, endIndent: 16),
                          child,
                        ],
                      ),
                  ],
                )
              else
                Padding(
                  padding: const .fromLTRB(72, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 4,
                    children: [
                      for (final item in widget.items.take(3))
                        _GroupPreview(item: item),
                      if (widget.items.length > 3)
                        Text('+${widget.items.length - 3} more', style: meta),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupPreview extends StatelessWidget {
  const _GroupPreview({required this.item});

  final Map item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = item['summary'] as String? ?? '';
    final body = (item['body'] as List? ?? const [])
        .whereType<Map>()
        .map((run) => run['text'] ?? '')
        .join()
        .replaceAll('\n', ' ');
    return Row(
      spacing: 8,
      children: [
        NotificationLeading(data: item, size: 16),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title.isEmpty ? '' : '$title  ',
              style: const TextStyle(fontWeight: .w500),
              children: [
                TextSpan(
                  text: body,
                  style: TextStyle(
                    fontWeight: .normal,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 20 / 14),
          ),
        ),
      ],
    );
  }
}
