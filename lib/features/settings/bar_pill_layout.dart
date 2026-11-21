import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../popups/bar_popup.dart';
import 'bar_live_pills.dart';
import 'bar_pill_panel.dart';
import 'bar_preference_models.dart';

const barResourceNames = {
  'cpu': 'CPU',
  'memory': 'Memory',
  'gpu': 'GPU',
  'network': 'Network',
};

/// Position of the bar, then each group as a card with one row per pill, a
/// zone that starts a new group, and the hidden pills last. Every pill shows
/// live and expands into the same kind of panel.
class BarPillLayoutEditor extends StatefulWidget {
  const BarPillLayoutEditor({
    super.key,
    required this.layout,
    required this.bottom,
    required this.onChanged,
    required this.onBottom,
    required this.options,
  });

  final BarLayout layout;
  final bool bottom;

  /// Null while a change is being saved.
  final ValueChanged<BarLayout>? onChanged;
  final ValueChanged<bool>? onBottom;

  /// Rows of pill-specific settings for a pill's panel.
  final List<Widget> Function(String id) options;

  @override
  State<BarPillLayoutEditor> createState() => _BarPillLayoutEditorState();
}

class _BarPillLayoutEditorState extends State<BarPillLayoutEditor> {
  String? _expanded;

  @override
  Widget build(BuildContext context) => BarLivePills(
    builder: (context, live) {
      final layout = widget.layout;
      final set = widget.onChanged;
      final reset = layout.withGroups(
        BarLayout.defaults.groups,
        center: BarLayout.defaults.center,
      );
      final rows = _PillRows(
        layout: layout,
        live: live,
        expanded: _expanded,
        onChanged: set,
        onExpand: (id) =>
            setState(() => _expanded = _expanded == id ? null : id),
        panel: (id) => barPillPanel(
          id,
          layout: layout,
          options: widget.options(id),
          onChanged: set,
        ),
      );
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          SettingsGroup(
            title: 'Bar',
            children: [
              SettingRow(
                id: 'position',
                label: const SettingLabel(
                  'Position',
                  description: 'Screen edge the bar sits on',
                ),
                control: SettingsSegmentedButton<bool>(
                  segments: const [
                    SettingsSegment(
                      false,
                      'Top',
                      icon: Icon(Icons.vertical_align_top_rounded),
                    ),
                    SettingsSegment(
                      true,
                      'Bottom',
                      icon: Icon(Icons.vertical_align_bottom_rounded),
                    ),
                  ],
                  selected: widget.bottom,
                  onSelected: widget.onBottom,
                ),
              ),
            ],
          ),
          SettingsSectionTitle(
            'Pills',
            trailing: TextButton.icon(
              onPressed: set == null || reset == layout
                  ? null
                  : () => set(reset),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset'),
            ),
          ),
          Padding(
            padding: const .only(bottom: 8),
            child: Text(
              'Groups run left to right across the bar. Drag pills to '
              'rearrange them.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _Lane(rows: rows),
          const SizedBox(height: 16),
          _HiddenPills(rows: rows),
        ],
      );
    },
  );
}

/// What every pill row needs, shared by the group and hidden cards.
class _PillRows {
  const _PillRows({
    required this.layout,
    required this.live,
    required this.expanded,
    required this.onChanged,
    required this.onExpand,
    required this.panel,
  });

  final BarLayout layout;
  final BarLiveBuilder? live;
  final String? expanded;
  final ValueChanged<BarLayout>? onChanged;
  final ValueChanged<String> onExpand;
  final List<Widget> Function(String id) panel;

  bool get enabled => onChanged != null;

  void set(BarLayout next) => onChanged?.call(next);

  Widget row(String id, {ValueChanged<String>? drop}) => _InsertTarget(
    enabled: enabled && drop != null,
    onDrop: drop ?? (_) {},
    child: _PillRow(id: id, rows: this),
  );
}

/// A dragged group, as opposed to a dragged pill ID.
class _GroupDrag {
  const _GroupDrag(this.index);
  final int index;
}

/// The group cards in bar order. Drops between them, or on the zone after
/// the last one, start a new group there.
class _Lane extends StatelessWidget {
  const _Lane({required this.rows});
  final _PillRows rows;

  @override
  Widget build(BuildContext context) {
    final layout = rows.layout;
    final groups = layout.groups;
    void drop(Object data, int gap) => switch (data) {
      final String id => rows.set(layout.insertGroup(id, gap)),
      _GroupDrag(:final index) when gap != index && gap != index + 1 =>
        rows.set(layout.moveGroup(index, gap > index ? gap - 1 : gap)),
      _ => null,
    };
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (var i = 0; i <= groups.length; i++) ...[
          _Gap(
            enabled: rows.enabled,
            last: i == groups.length,
            accepts: (data) => switch (data) {
              String() => true,
              _GroupDrag(:final index) => i != index && i != index + 1,
              _ => false,
            },
            onDrop: (data) => drop(data, i),
          ),
          if (i < groups.length) _Group(index: i, rows: rows),
        ],
      ],
    );
  }
}

/// Space between groups that opens while a drop would start a group there.
/// The [last] one always shows as the New group zone.
class _Gap extends StatelessWidget {
  const _Gap({
    required this.enabled,
    required this.last,
    required this.accepts,
    required this.onDrop,
  });

  final bool enabled;
  final bool last;
  final bool Function(Object? data) accepts;
  final ValueChanged<Object> onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => enabled && accepts(details.data),
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        final open = active || last;
        final color = active ? colors.onPrimaryContainer : colors.primary;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: open ? 64 : 16,
          margin: .only(top: last ? 16 : 0, bottom: open && !last ? 16 : 0),
          decoration: ShapeDecoration(
            color: active ? colors.primaryContainer : null,
            shape: RoundedRectangleBorder(
              borderRadius: .circular(28),
              side: last && !active
                  ? BorderSide(color: colors.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          child: open
              ? Row(
                  mainAxisAlignment: .center,
                  spacing: 8,
                  children: [
                    Icon(Icons.add_rounded, color: color),
                    Text(
                      'New group',
                      style: text.labelLarge?.copyWith(color: color),
                    ),
                    if (!active)
                      Text(
                        '· Drop a pill here',
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

/// Tracks the pointer so drag handles and quick actions show on hover.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  void _set(bool hovered) {
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _set(true),
    onExit: (_) => _set(false),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _set,
      child: widget.builder(context, _hovered),
    ),
  );
}

/// A drag handle that fades in with [visible].
class _Handle extends StatelessWidget {
  const _Handle({required this.visible, required this.enabled});
  final bool visible;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: visible && enabled ? 1 : 0,
    child: MouseRegion(
      cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
      child: Icon(
        Icons.drag_indicator_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One group: a header that drags the group and centers it, then its pills.
class _Group extends StatelessWidget {
  const _Group({required this.index, required this.rows});

  final int index;
  final _PillRows rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final layout = rows.layout;
    final pills = layout.groups[index];
    final center = layout.center;
    final side = switch (center) {
      null => null,
      _ when center == index => 'Centered',
      _ when index < center => 'Left side',
      _ => 'Right side',
    };
    // Index after the dragged pill leaves this group.
    int target(String id, int position) {
      final from = pills.indexOf(id);
      return from >= 0 && from < position ? position - 1 : position;
    }

    final header = _Hover(
      builder: (context, hovered) => Padding(
        padding: const .fromLTRB(8, 8, 8, 8),
        child: Row(
          spacing: 12,
          children: [
            Draggable<Object>(
              data: _GroupDrag(index),
              maxSimultaneousDrags: rows.enabled ? 1 : 0,
              feedback: Material(
                color: colors.secondaryContainer,
                borderRadius: .circular(16),
                elevation: 3,
                child: Padding(
                  padding: const .all(12),
                  child: Text(
                    pills.map((id) => barPillNames[id]).join(' · '),
                    style: text.labelLarge,
                  ),
                ),
              ),
              child: Tooltip(
                message: 'Drag to reorder groups',
                child: _Handle(visible: hovered, enabled: rows.enabled),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Group ${index + 1}',
                  children: [
                    if (side != null)
                      TextSpan(
                        text: '   $side',
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                overflow: .ellipsis,
                style: text.titleMedium?.copyWith(color: colors.primary),
              ),
            ),
            FilterChip(
              label: const Text('Center'),
              tooltip: 'Center this group on the bar',
              selected: center == index,
              onSelected: rows.enabled
                  ? (on) => rows.set(layout.withCenter(on ? index : null))
                  : null,
            ),
          ],
        ),
      ),
    );

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          rows.enabled && details.data is String,
      onAcceptWithDetails: (details) =>
          rows.set(layout.movePill(details.data as String, index)),
      builder: (context, candidates, _) => _Card(
        active: candidates.isNotEmpty,
        children: [
          header,
          for (var j = 0; j < pills.length; j++)
            rows.row(
              pills[j],
              drop: (id) {
                if (id != pills[j]) {
                  rows.set(layout.movePill(id, index, target(id, j)));
                }
              },
            ),
        ],
      ),
    );
  }
}

/// The surface of one group, a tone below its pill rows and tinted while a
/// drop would land in it.
class _Card extends StatelessWidget {
  const _Card({required this.active, required this.children});

  final bool active;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const .fromLTRB(8, 4, 8, 8),
      decoration: ShapeDecoration(
        color: active
            ? colors.secondaryContainer
            : colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: .circular(28)),
      ),
      child: Column(crossAxisAlignment: .stretch, children: children),
    );
  }
}

/// Marks where a dropped pill lands: above this row.
class _InsertTarget extends StatelessWidget {
  const _InsertTarget({
    required this.enabled,
    required this.onDrop,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<String> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (details) => enabled && details.data is String,
    onAcceptWithDetails: (details) => onDrop(details.data as String),
    builder: (context, candidates, _) => Column(
      crossAxisAlignment: .stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: candidates.isEmpty ? 4 : 8,
          padding: .only(top: candidates.isEmpty ? 4 : 2, bottom: 2),
          margin: const .symmetric(horizontal: 16),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: candidates.isEmpty
                  ? null
                  : Theme.of(context).colorScheme.primary,
              shape: const StadiumBorder(),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

/// A pill's one-line role, so its trigger reads without opening it.
String _summary(String id, BarLayout layout) {
  if (layout.hidden.contains(id)) return 'Hidden';
  if (barCardPillIds.contains(id)) {
    return layout.clickCards.contains(id)
        ? 'Card opens on click'
        : 'Card opens on hover';
  }
  return switch (id) {
    'notifications' => 'Click for notifications',
    'sidebar' => 'Click for quick settings',
    'workspaces' => '${layout.workspaceCount} workspaces',
    'window' => 'Focused window',
    _ => 'Running apps',
  };
}

/// One pill as a list item: drag it anywhere, hide or show it from the
/// hover action, and tap it to open its panel.
class _PillRow extends StatelessWidget {
  const _PillRow({required this.id, required this.rows});

  final String id;
  final _PillRows rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final layout = rows.layout;
    final expanded = rows.expanded == id;
    final hidden = layout.hidden.contains(id);
    final panel = rows.panel(id);
    final pill = BarLivePill(id: id, layout: layout, live: rows.live);
    final theme = BarPopupScope.maybeThemeOf(context);
    // Quick settings is the way back to everything else.
    final action = switch ((hidden, id)) {
      (true, _) => (
        tip: 'Show',
        icon: Icons.visibility_outlined,
        next: () => layout.insertGroup(id, layout.groups.length),
      ),
      (false, 'sidebar') => null,
      _ => (
        tip: 'Hide',
        icon: Icons.visibility_off_outlined,
        next: () => layout.hidePill(id),
      ),
    };

    Widget header(bool hovered) => Semantics(
      button: panel.isNotEmpty,
      expanded: panel.isEmpty ? null : expanded,
      child: InkWell(
        onTap: panel.isEmpty ? null : () => rows.onExpand(id),
        mouseCursor: rows.enabled
            ? SystemMouseCursors.grab
            : SystemMouseCursors.click,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const .fromLTRB(8, 8, 12, 8),
            child: Row(
              spacing: 12,
              children: [
                _Handle(visible: hovered, enabled: rows.enabled),
                SizedBox(
                  width: 168,
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(
                        barPillNames[id]!,
                        overflow: .ellipsis,
                        style: text.bodyLarge,
                      ),
                      Text(
                        _summary(id, layout),
                        overflow: .ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Pills share one left edge so rows read as a column.
                Expanded(
                  child: Align(
                    alignment: .centerLeft,
                    child: Opacity(opacity: hidden ? .55 : 1, child: pill),
                  ),
                ),
                if (action != null)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: hovered || hidden ? 1 : 0,
                    child: IconButton(
                      key: ValueKey('${action.tip.toLowerCase()}-$id'),
                      tooltip: action.tip,
                      onPressed: rows.enabled
                          ? () => rows.set(action.next())
                          : null,
                      icon: Icon(action.icon),
                    ),
                  ),
                SizedBox(
                  width: 24,
                  child: panel.isEmpty
                      ? null
                      : AnimatedRotation(
                          turns: expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // A tone above its group and below the pill, which is container-high.
    return Material(
      color: colors.surfaceContainer,
      borderRadius: .circular(20),
      clipBehavior: .antiAlias,
      child: _Hover(
        builder: (context, hovered) => Column(
          crossAxisAlignment: .stretch,
          children: [
            Draggable<Object>(
              data: id,
              maxSimultaneousDrags: rows.enabled ? 1 : 0,
              feedback: Material(
                type: .transparency,
                child: theme == null
                    ? pill
                    : BarPopupScope(theme: theme, child: pill),
              ),
              childWhenDragging: Opacity(opacity: .3, child: header(false)),
              child: header(hovered),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Easing.emphasizedDecelerate,
              alignment: .topCenter,
              child: expanded && panel.isNotEmpty
                  ? Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        settingsRows(panel),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pills off the bar, in their default order; dropping a pill here hides it.
class _HiddenPills extends StatelessWidget {
  const _HiddenPills({required this.rows});
  final _PillRows rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final layout = rows.layout;
    final hidden = layout.hidden;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          rows.enabled &&
          details.data is String &&
          details.data != 'sidebar' &&
          !hidden.contains(details.data),
      onAcceptWithDetails: (details) =>
          rows.set(layout.hidePill(details.data as String)),
      builder: (context, candidates, _) => _Card(
        active: candidates.isNotEmpty,
        children: [
          Padding(
            padding: const .fromLTRB(8, 12, 8, 12),
            child: Row(
              spacing: 12,
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  key: const ValueKey('hidden-pills'),
                  color: colors.onSurfaceVariant,
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Hidden',
                      children: [
                        TextSpan(
                          text: '   Drop a pill here to hide it',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    overflow: .ellipsis,
                    style: text.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final id in hidden) rows.row(id),
        ],
      ),
    );
  }
}
