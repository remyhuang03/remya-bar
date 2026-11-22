import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../popups/popup_measure.dart';
import 'notification_flow.dart';
import 'notification_group.dart';
import 'notification_tile.dart';

/// Manual choices survive closing the native popup for the bar session.
class NotificationExpansion {
  final rows = <int, bool>{};
  final groups = <(int, Object?), bool>{};

  void retain(List<Map> items) {
    final ids = items.map((item) => item['id']).toSet();
    final groupsBySection = items
        .map((item) => (item['urgency'] as int? ?? 1, item['group']))
        .toSet();
    rows.removeWhere((id, _) => !ids.contains(id));
    groups.removeWhere((group, _) => !groupsBySection.contains(group));
  }
}

class NotificationCenterCard extends StatefulWidget {
  const NotificationCenterCard({
    super.key,
    required this.data,
    required this.onAction,
    this.onHeight,
    this.tasks,
    this.expansion,
    this.actionError,
  });

  final Map<String, Object?> data;
  final NotificationAction onAction;
  final ValueChanged<double>? onHeight;
  final Widget? tasks;
  final NotificationExpansion? expansion;
  final String? actionError;

  @override
  State<NotificationCenterCard> createState() => _NotificationCenterCardState();
}

class _NotificationCenterCardState extends State<NotificationCenterCard> {
  late final _expansion = widget.expansion ?? NotificationExpansion();
  final _focus = <Object, FocusNode>{};
  final _panelFocus = FocusNode();
  bool _keyboard = false;
  final _scroll = ScrollController();
  List<Object> _visibleRows = [];
  Object? _tabRow;
  bool _initialFocus = true;
  double? _topHeight;
  double? _listHeight;
  double? _footerHeight;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && _panelFocus.hasFocus && !_keyboard) {
      setState(() => _keyboard = true);
    }
    return .ignored;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKeyEvent);
    _panelFocus.dispose();
    _scroll.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _rowFocus(Object id) =>
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'Notification $id'));

  void _focusRow(Object id, {bool up = false}) {
    final node = _focus[id];
    node?.requestFocus();
    if (node?.context case final context?) {
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: up ? .keepVisibleAtStart : .keepVisibleAtEnd,
      );
    }
  }

  void _moveFocus(int direction) {
    if (_visibleRows.isEmpty) return;
    final current = _visibleRows.indexWhere(
      (id) => _focus[id]?.hasFocus == true,
    );
    final index = (current + direction).clamp(0, _visibleRows.length - 1);
    _focusRow(_visibleRows[index], up: direction < 0);
  }

  void _rowFocused(Object id, bool focused) {
    if (focused && _tabRow != id && mounted) {
      setState(() => _tabRow = id);
    }
  }

  Widget _traversal(Object id, Widget child, {Key? key}) => FocusTraversalGroup(
    key: key,
    descendantsAreTraversable:
        _tabRow == id ||
        (_tabRow == null && (widget.onHeight == null || _focus.isEmpty)),
    child: child,
  );

  void _updateFocus(List<Object> rows) {
    final focused = _visibleRows.indexWhere(
      (id) => _focus[id]?.hasFocus == true,
    );
    final removed = focused >= 0 && !rows.contains(_visibleRows[focused]);
    _visibleRows = rows;
    if (rows.isEmpty || (!_initialFocus && !removed)) return;
    _initialFocus = false;
    final next = rows[removed ? focused.clamp(0, rows.length - 1) : 0];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visibleRows.contains(next)) _focusRow(next);
    });
  }

  void _reportHeight(double pad) {
    if ((_topHeight, _listHeight, _footerHeight) case (
      final top?,
      final list?,
      final footer?,
    )) {
      widget.onHeight?.call(top + list + footer + pad * 2 + 32);
    }
  }

  void _clear([int? urgency, Object? group]) => widget.onAction({
    'action': 'notification.clear',
    'urgency': ?urgency,
    'group': ?group,
  });

  @override
  Widget build(BuildContext context) {
    final items = (widget.data['notifications'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final error = widget.data['serviceError'] as String?;
    if (error == null) _expansion.retain(items);
    final sections = <int, Map<Object?, List<Map>>>{2: {}, 1: {}, 0: {}};
    for (final item in items) {
      final groups = sections[item['urgency']] ?? sections[1]!;
      (groups[item['group']] ??= []).add(item);
    }
    final first = sections.values
        .expand((groups) => groups.values)
        .firstOrNull
        ?.first['id'];
    final focusOrder = <Object>[];
    Widget tile(
      Map item,
      int urgency,
      Object? group, {
      required bool child,
      required BorderRadius radius,
    }) {
      final id = item['id'] as int;
      final rowKey = (urgency, group, id, child);
      focusOrder.add(rowKey);
      final expanded =
          urgency == 2 || (_expansion.rows[id] ?? (!child && id == first));
      return _traversal(
        rowKey,
        key: ValueKey(id),
        NotificationTile(
          data: item,
          expanded: expanded,
          onToggle: urgency == 2
              ? null
              : () => setState(() => _expansion.rows[id] = !expanded),
          focusNode: _rowFocus(rowKey),
          showFocusIndicator: _keyboard,
          onFocusChange: (focused) => _rowFocused(rowKey, focused),
          radius: radius,
          onAction: widget.onAction,
          onDismissSection: () => _clear(urgency, child ? group : null),
        ),
      );
    }

    Widget section(int urgency, Map<Object?, List<Map>> groups) {
      final children = <Widget>[];
      for (final (index, entry) in groups.entries.indexed) {
        final MapEntry(key: group, value: members) = entry;
        final radius = BorderRadius.vertical(
          top: Radius.circular(index == 0 ? 28 : 4),
          bottom: Radius.circular(index == groups.length - 1 ? 28 : 4),
        );
        if (members.length == 1) {
          children.add(
            tile(members.first, urgency, group, child: false, radius: radius),
          );
          continue;
        }
        final key = (urgency, group);
        final expanded =
            urgency == 2 ||
            (_expansion.groups[key] ?? (members.first['id'] == first));
        focusOrder.add(key);
        children.add(
          NotificationGroup(
            key: ValueKey(key),
            items: members,
            expanded: expanded,
            radius: radius,
            focusNode: _rowFocus(key),
            showFocusIndicator: _keyboard,
            traversable:
                _tabRow == key || (_tabRow == null && widget.onHeight == null),
            onFocusChange: (focused) => _rowFocused(key, focused),
            onToggle: urgency == 2
                ? null
                : () => setState(() => _expansion.groups[key] = !expanded),
            onDismiss: members.any((item) => item['resident'] != true)
                ? () => _clear(urgency, group)
                : null,
            onDismissSection: () => _clear(urgency),
            children: [
              if (expanded)
                for (final item in members)
                  tile(
                    item,
                    urgency,
                    group,
                    child: true,
                    radius: BorderRadius.zero,
                  ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (urgency == 0)
            _SilentHeader(
              onClear:
                  groups.values
                      .expand((items) => items)
                      .any((item) => item['resident'] != true)
                  ? () => _clear(0)
                  : null,
            ),
          NotificationFlow(spacing: 2, children: children),
        ],
      );
    }

    final dnd = widget.data['dnd'] as bool?;
    final quiet = widget.data['quietReason'];
    final status = switch ((quiet, widget.data['quietUntilMinutes'])) {
      ('schedule', final int minutes) =>
        'Do not disturb · until ${_scheduleTime(minutes)}',
      ('schedule', _) => 'Do not disturb · schedule',
      ('fullscreen', _) => 'Do not disturb · fullscreen app',
      ('manual', _) => 'Do not disturb',
      _ => switch (items.length) {
        0 => 'You’re all caught up',
        1 => '1 notification',
        final count => '$count notifications',
      },
    };
    final panel = widget.onHeight != null;
    final body = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        if (quiet != null)
          const _StatusBanner(
            message:
                'Notifications arrive silently. Critical alerts still show.',
          ),
        if (error != null)
          _StatusBanner(
            message: error,
            error: true,
            onRetry: () =>
                widget.onAction(const {'action': 'notification.retry'}),
          )
        else if (items.isEmpty)
          const _EmptyNotifications(),
        if (widget.actionError case final message?)
          _StatusBanner(message: message, error: true),
        if (error == null)
          NotificationFlow(
            spacing: 16,
            children: [
              for (final MapEntry(key: urgency, value: groups)
                  in sections.entries)
                if (groups.isNotEmpty)
                  KeyedSubtree(
                    key: ValueKey(urgency),
                    child: section(urgency, groups),
                  ),
            ],
          ),
        if (widget.tasks case final tasks?) ...[
          const Divider(height: 1),
          tasks,
        ],
      ],
    );
    if (panel) {
      _updateFocus(focusOrder);
    } else {
      _visibleRows = focusOrder;
    }

    _focus.removeWhere((id, node) {
      if (focusOrder.contains(id) || node.context != null) return false;
      node.dispose();
      return true;
    });
    final clearCritical = widget.data['clearCritical'] == true;
    final canClear = items.any(
      (item) =>
          item['resident'] != true && (clearCritical || item['urgency'] != 2),
    );
    final criticalRemains = items.any(
      (item) => item['urgency'] == 2 && item['resident'] != true,
    );
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        if (panel)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              widget.onAction(const {'action': 'close'}),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveFocus(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveFocus(1),
      },
      child: Focus(
        focusNode: _panelFocus,
        autofocus: panel,
        child: Listener(
          onPointerDown: (_) {
            if (_keyboard) setState(() => _keyboard = false);
          },
          child: Material(
            type: panel ? .card : .transparency,
            color: panel ? colors.surfaceContainer : null,
            shape: panel
                ? RoundedRectangleBorder(
                    borderRadius: .circular(32),
                    side: BorderSide(color: colors.surfaceContainerHighest),
                  )
                : null,
            clipBehavior: panel ? .antiAlias : .none,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pad = !panel
                    ? 0.0
                    : (constraints.maxWidth < 340 ? 12.0 : 24.0);
                return Padding(
                  padding: .symmetric(vertical: pad),
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .stretch,
                    spacing: 16,
                    children: [
                      Padding(
                        padding: .symmetric(horizontal: pad),
                        child: PopupMeasure(
                          onHeight: (height) {
                            _topHeight = height;
                            _reportHeight(pad);
                          },
                          child: _NotificationHeader(
                            status: status,
                            onSettings: () => widget.onAction(const {
                              'action': 'notification.settings',
                            }),
                          ),
                        ),
                      ),
                      Flexible(
                        child: _NotificationScroll(
                          controller: _scroll,
                          pad: pad,
                          child: PopupMeasure(
                            onHeight: (height) {
                              _listHeight = height;
                              _reportHeight(pad);
                            },
                            child: body,
                          ),
                        ),
                      ),
                      Padding(
                        padding: .symmetric(horizontal: pad),
                        child: PopupMeasure(
                          onHeight: (height) {
                            _footerHeight = height;
                            _reportHeight(pad);
                          },
                          child: _NotificationFooter(
                            dnd: dnd,
                            showClear: items.isNotEmpty,
                            onDnd: (value) => widget.onAction({
                              'action': 'notification.dnd',
                              'value': value,
                            }),
                            onClear: canClear ? _clear : null,
                            clearHint: criticalRemains && !clearCritical
                                ? 'Critical notifications must be dismissed individually'
                                : 'Resident notifications must be dismissed individually',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader({required this.status, required this.onSettings});

  final String status;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.headlineSmall?.copyWith(
                  height: 30 / 24,
                  fontWeight: .bold,
                  color: colors.primary,
                ),
              ),
              Text(status, style: _supporting(theme)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _NotificationFooter extends StatelessWidget {
  const _NotificationFooter({
    required this.dnd,
    required this.showClear,
    required this.onDnd,
    required this.onClear,
    required this.clearHint,
  });

  final bool? dnd;
  final bool showClear;
  final ValueChanged<bool> onDnd;
  final VoidCallback? onClear;
  final String clearHint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final clear = FilledButton.tonal(
      onPressed: onClear,
      child: const Text('Clear all'),
    );
    return Wrap(
      alignment: .spaceBetween,
      crossAxisAlignment: .center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Semantics(
          toggled: dnd,
          child: FilledButton.icon(
            style: dnd == true
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: colors.secondaryContainer,
                    foregroundColor: colors.onSecondaryContainer,
                  ),
            onPressed: dnd == null ? null : () => onDnd(!dnd!),
            icon: const Icon(Icons.do_not_disturb_on_outlined, size: 20),
            label: const Text('Do not disturb'),
          ),
        ),
        if (showClear)
          onClear == null ? Tooltip(message: clearHint, child: clear) : clear,
      ],
    );
  }
}

class _SilentHeader extends StatelessWidget {
  const _SilentHeader({this.onClear});

  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const .fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Silent',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Clear section',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    this.error = false,
    this.onRetry,
  });

  final String message;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: error ? colors.errorContainer : colors.surfaceContainerHigh,
      borderRadius: .circular(20),
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 12),
        child: Row(
          spacing: 12,
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.do_not_disturb_on_outlined,
              size: 20,
              color: error ? colors.onErrorContainer : colors.primary,
            ),
            Expanded(
              child: Text(
                message,
                style: _supporting(theme)?.copyWith(
                  color: error
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const .symmetric(vertical: 32),
      child: Column(
        spacing: 12,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.surfaceContainerHigh,
            child: Icon(
              Icons.notifications_none_rounded,
              size: 24,
              color: colors.onSurfaceVariant,
            ),
          ),
          Text('No notifications', style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _NotificationScroll extends StatefulWidget {
  const _NotificationScroll({
    required this.controller,
    required this.pad,
    required this.child,
  });

  final ScrollController controller;
  final double pad;
  final Widget child;

  @override
  State<_NotificationScroll> createState() => _NotificationScrollState();
}

class _NotificationScrollState extends State<_NotificationScroll> {
  bool _top = false;
  bool _bottom = false;

  bool _metrics(ScrollMetrics metrics) {
    final top = metrics.extentBefore > 0;
    final bottom = metrics.extentAfter > 0;
    if (top != _top || bottom != _bottom) {
      setState(() {
        _top = top;
        _bottom = bottom;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) => _metrics(event.metrics),
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (event) => _metrics(event.metrics),
          child: SingleChildScrollView(
            controller: widget.controller,
            primary: false,
            padding: .symmetric(horizontal: widget.pad),
            child: widget.child,
          ),
        ),
      ),
      if (_top)
        Positioned(
          top: 0,
          left: widget.pad,
          right: widget.pad,
          child: const Divider(height: 1),
        ),
      if (_bottom)
        Positioned(
          bottom: 0,
          left: widget.pad,
          right: widget.pad,
          child: const Divider(height: 1),
        ),
    ],
  );
}

TextStyle? _supporting(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
  fontSize: 13,
  height: 18 / 13,
);

String _scheduleTime(int minutes) {
  final hours = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hours:$minute';
}
