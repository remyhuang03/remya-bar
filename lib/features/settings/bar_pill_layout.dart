import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../popups/bar_popup.dart';
import 'bar_live_pills.dart';
import 'bar_pill_inspector.dart';
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

const barResourceNames = {
  'cpu': 'CPU',
  'memory': 'Memory',
  'gpu': 'GPU',
  'network': 'Network',
};

/// The bar as it will look, the pills in their groups, and the options of
/// the selected pill. Every pill is the real, live pill.
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

  /// Rows of pill-specific settings for the inspector.
  final List<Widget> Function(String id) options;

  @override
  State<BarPillLayoutEditor> createState() => _BarPillLayoutEditorState();
}

class _BarPillLayoutEditorState extends State<BarPillLayoutEditor> {
  String? _selected;

  BarLayout get _layout => widget.layout;

  void _set(BarLayout next) => widget.onChanged?.call(next);

  // Only pills with options of their own open the inspector.
  void _select(String id) => setState(
    () => _selected = _selected == id || widget.options(id).isEmpty ? null : id,
  );

  @override
  Widget build(BuildContext context) => BarLivePills(
    builder: (context, live) {
      final layout = _layout;
      final reset = layout.withGroups(
        BarLayout.defaults.groups,
        center: BarLayout.defaults.center,
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
                control: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.vertical_align_top_rounded),
                      label: Text('Top'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.vertical_align_bottom_rounded),
                      label: Text('Bottom'),
                    ),
                  ],
                  selected: {widget.bottom},
                  onSelectionChanged: widget.onBottom == null
                      ? null
                      : (value) => widget.onBottom!(value.single),
                ),
              ),
            ],
          ),
          SettingsSectionTitle(
            'Pills',
            trailing: TextButton.icon(
              onPressed: widget.onChanged == null || reset == layout
                  ? null
                  : () => _set(reset),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset'),
            ),
          ),
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 16,
              children: [
                _Lane(
                  layout: layout,
                  live: live,
                  selected: _selected,
                  enabled: widget.onChanged != null,
                  onSelect: _select,
                  onChanged: _set,
                ),
                _HiddenPills(
                  layout: layout,
                  live: live,
                  selected: _selected,
                  enabled: widget.onChanged != null,
                  onSelect: _select,
                  onChanged: _set,
                ),
                Text(
                  'Drag pills to rearrange them, or between groups to start '
                  'a new group. Right-click a pill for how its card opens, '
                  'centering and hiding. Select a pill for its own options.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Easing.emphasizedDecelerate,
            alignment: .topCenter,
            child: switch (_selected) {
              final id? => BarPillInspector(
                key: ValueKey(id),
                id: id,
                options: widget.options(id),
              ),
              null => const SizedBox(width: double.infinity),
            },
          ),
        ],
      );
    },
  );
}

/// A dragged group, as opposed to a dragged pill ID.
class _GroupDrag {
  const _GroupDrag(this.index);
  final int index;
}

/// The groups in bar order, with drop gaps that start new groups.
class _Lane extends StatelessWidget {
  const _Lane({
    required this.layout,
    required this.live,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
  });

  final BarLayout layout;
  final BarLiveBuilder? live;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<BarLayout> onChanged;

  void _dropAtGap(Object data, int gap) => switch (data) {
    final String id => onChanged(layout.insertGroup(id, gap)),
    _GroupDrag(:final index) when gap != index && gap != index + 1 => onChanged(
      layout.moveGroup(index, gap > index ? gap - 1 : gap),
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final groups = layout.groups;
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (var i = 0; i <= groups.length; i++) ...[
          _Gap(
            enabled: enabled,
            accepts: (data) => switch (data) {
              String() => true,
              _GroupDrag(:final index) => i != index && i != index + 1,
              _ => false,
            },
            onDrop: (data) => _dropAtGap(data, i),
          ),
          if (i < groups.length)
            _Group(
              index: i,
              layout: layout,
              live: live,
              selected: selected,
              enabled: enabled,
              onSelect: onSelect,
              onChanged: onChanged,
            ),
        ],
      ],
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap({
    required this.enabled,
    required this.accepts,
    required this.onDrop,
  });

  final bool enabled;
  final bool Function(Object? data) accepts;
  final ValueChanged<Object> onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => enabled && accepts(details.data),
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: active ? 48 : 12,
          margin: const .symmetric(vertical: 2),
          decoration: ShapeDecoration(
            color: active ? colors.primaryContainer : null,
            shape: RoundedRectangleBorder(borderRadius: .circular(16)),
          ),
          child: active
              ? Row(
                  mainAxisAlignment: .center,
                  spacing: 8,
                  children: [
                    Icon(Icons.add_rounded, color: colors.onPrimaryContainer),
                    Text(
                      'New group',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.index,
    required this.layout,
    required this.live,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
  });

  final int index;
  final BarLayout layout;
  final BarLiveBuilder? live;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<BarLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pills = layout.groups[index];
    final centered = layout.center == index;
    // Index after the dragged pill leaves this group.
    int target(String id, int position) {
      final from = pills.indexOf(id);
      return from >= 0 && from < position ? position - 1 : position;
    }

    Widget frame(bool active) => _Row(
      active: active,
      label: Draggable<Object>(
        data: _GroupDrag(index),
        maxSimultaneousDrags: enabled ? 1 : 0,
        feedback: Material(
          color: colors.secondaryContainer,
          borderRadius: .circular(16),
          elevation: 3,
          child: Padding(
            padding: const .all(12),
            child: Text(
              pills.map((id) => barPillNames[id]).join(' · '),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
          child: Tooltip(
            message: 'Drag to reorder groups',
            child: Row(
              spacing: 4,
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        'Group ${index + 1}',
                        overflow: .ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (centered)
                        Text(
                          'Centered',
                          overflow: .ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.tertiary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      children: [
        for (var j = 0; j < pills.length; j++)
          _InsertTarget(
            enabled: enabled,
            onDrop: (id) {
              if (id != pills[j]) {
                onChanged(layout.movePill(id, index, target(id, j)));
              }
            },
            child: _PillTile(
              id: pills[j],
              layout: layout,
              live: live,
              selected: selected == pills[j],
              enabled: enabled,
              onSelect: onSelect,
              onChanged: onChanged,
            ),
          ),
      ],
    );

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => enabled && details.data is String,
      onAcceptWithDetails: (details) =>
          onChanged(layout.movePill(details.data as String, index)),
      builder: (context, candidates, _) => frame(candidates.isNotEmpty),
    );
  }
}

/// One aligned editor row: a fixed label column, then wrapping pills.
class _Row extends StatelessWidget {
  const _Row({
    required this.active,
    required this.label,
    required this.children,
    this.empty,
  });

  final bool active;
  final Widget label;
  final List<Widget> children;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const .symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: active ? colors.secondaryContainer : colors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: .circular(20)),
      ),
      child: Row(
        children: [
          SizedBox(width: 108, child: label),
          Expanded(
            child: children.isEmpty
                ? (empty ?? const SizedBox.shrink())
                : Wrap(
                    crossAxisAlignment: .center,
                    spacing: 4,
                    runSpacing: 4,
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Marks where a dropped pill lands: before this pill.
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
    builder: (context, candidates, _) => Row(
      mainAxisSize: .min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: candidates.isEmpty ? 6 : 4,
          height: 40,
          margin: .only(right: candidates.isEmpty ? 0 : 4),
          decoration: ShapeDecoration(
            color: candidates.isEmpty
                ? null
                : Theme.of(context).colorScheme.primary,
            shape: const StadiumBorder(),
          ),
        ),
        child,
      ],
    ),
  );
}

/// One live pill that can be selected and dragged.
class _PillTile extends StatelessWidget {
  const _PillTile({
    required this.id,
    required this.layout,
    required this.live,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
    this.dimmed = false,
  });

  final String id;
  final BarLayout layout;
  final BarLiveBuilder? live;
  final bool selected;
  final bool enabled;
  final bool dimmed;
  final ValueChanged<String> onSelect;
  final ValueChanged<BarLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pill = BarLivePill(id: id, layout: layout, live: live);
    final theme = BarPopupScope.maybeThemeOf(context);
    return Draggable<Object>(
      data: id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        type: .transparency,
        child: theme == null ? pill : BarPopupScope(theme: theme, child: pill),
      ),
      childWhenDragging: Opacity(opacity: .3, child: pill),
      child: MenuAnchor(
        menuChildren: barPillMenu(id, layout, enabled ? onChanged : null),
        builder: (context, menu, _) => Semantics(
          button: true,
          selected: selected,
          label: barPillNames[id],
          excludeSemantics: true,
          onLongPress: menu.open,
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                menu.open(position: details.localPosition),
            child: InkWell(
              borderRadius: .circular(24),
              onTap: () => onSelect(id),
              onLongPress: menu.open,
              mouseCursor: enabled ? SystemMouseCursors.grab : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const .all(4),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: .circular(24),
                    side: BorderSide(
                      color: selected ? colors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Badge(
                  isLabelVisible: barCardPillIds.contains(id),
                  backgroundColor: colors.tertiaryContainer,
                  alignment: .bottomEnd,
                  offset: const Offset(-2, -10),
                  label: Icon(
                    layout.clickCards.contains(id)
                        ? Icons.ads_click_rounded
                        : Icons.mouse_outlined,
                    size: 10,
                    color: colors.onTertiaryContainer,
                  ),
                  child: Opacity(opacity: dimmed ? .55 : 1, child: pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        child: SizedBox(height: 40, child: Center(child: pill)),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 40,
      child: Center(
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

class _HiddenPills extends StatelessWidget {
  const _HiddenPills({
    required this.layout,
    required this.live,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
  });

  final BarLayout layout;
  final BarLiveBuilder? live;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<BarLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hidden = layout.hidden;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          enabled &&
          details.data is String &&
          details.data != 'sidebar' &&
          !hidden.contains(details.data),
      onAcceptWithDetails: (details) =>
          onChanged(layout.hidePill(details.data as String)),
      builder: (context, candidates, _) => _Row(
        active: candidates.isNotEmpty,
        label: Row(
          spacing: 4,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
            Flexible(
              child: Text(
                'Hidden',
                overflow: .ellipsis,
                style: text.labelLarge,
              ),
            ),
          ],
        ),
        empty: Text('Drop a pill here to hide it', style: text.bodySmall),
        children: [
          for (final id in hidden)
            _PillTile(
              id: id,
              layout: layout,
              live: live,
              selected: selected == id,
              enabled: enabled,
              dimmed: true,
              onSelect: onSelect,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
