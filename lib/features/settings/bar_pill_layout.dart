import 'package:material_ui/material_ui.dart';

import 'bar_preference_models.dart';

const barPillNames = {
  'notifications': 'Notifications',
  'window': 'Active window',
  'resources': 'System resources',
  'media': 'Media',
  'workspaces': 'Workspaces',
  'clock': 'Clock',
  'tray': 'App tray',
  'ai-usage': 'AI Usage',
  'battery': 'Battery',
  'sidebar': 'Quick settings',
};

const barResourceNames = {
  'cpu': 'CPU',
  'memory': 'Memory',
  'gpu': 'GPU',
  'network': 'Network',
};

/// A live miniature of the bar, followed by the editable groups.
class BarPillLayoutEditor extends StatelessWidget {
  const BarPillLayoutEditor({
    super.key,
    required this.layout,
    required this.showSeconds,
    required this.onChanged,
  });

  final BarLayout layout;
  final bool showSeconds;

  /// Null while a change is being saved.
  final ValueChanged<BarLayout>? onChanged;

  void _set(BarLayout next) => onChanged?.call(next);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final groups = layout.groups;
    final resetLayout = layout.withGroups(
      BarLayout.defaults.groups,
      center: BarLayout.defaults.center,
    );
    final hidden = layout.hidden;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Semantics(
          label: 'Bar preview',
          child: _BarPreview(layout: layout, showSeconds: showSeconds),
        ),
        Text(
          'Drag pills between groups, or select a pill for more actions. '
          'Drag a group by its handle to reorder it.',
          style: text.bodySmall,
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: groups.length,
          onReorderItem: (from, to) {
            if (onChanged != null) _set(layout.moveGroup(from, to));
          },
          itemBuilder: (context, i) => Padding(
            // Pill IDs are unique, so a group's pills identify it.
            key: ValueKey(groups[i].join(',')),
            padding: const .only(bottom: 12),
            child: _GroupCard(
              index: i,
              layout: layout,
              showSeconds: showSeconds,
              onChanged: onChanged == null ? null : _set,
            ),
          ),
        ),
        _NewGroupTarget(
          enabled: onChanged != null,
          onDrop: (id) => _set(layout.movePill(id, groups.length)),
        ),
        _DropArea(
          enabled: onChanged != null,
          accepts: (id) => id != 'sidebar' && !hidden.contains(id),
          onDrop: (id) => _set(layout.hidePill(id)),
          builder: (active) => _GroupFrame(
            active: active,
            outlined: true,
            header: Text('Hidden', style: text.labelLarge),
            child: hidden.isEmpty
                ? Text('Drag a pill here to hide it.', style: text.bodySmall)
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in hidden)
                        _Pill(
                          id: id,
                          layout: layout,
                          showSeconds: showSeconds,
                          enabled: onChanged != null,
                          actions: [
                            for (var i = 0; i < groups.length; i++)
                              (
                                'Show in group ${i + 1}',
                                Icons.visibility_rounded,
                                () => _set(layout.movePill(id, i)),
                              ),
                            (
                              'Show in new group',
                              Icons.add_rounded,
                              () => _set(layout.movePill(id, groups.length)),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ),
        Align(
          alignment: .centerRight,
          child: TextButton.icon(
            onPressed: onChanged == null || resetLayout == layout
                ? null
                : () => _set(resetLayout),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset layout'),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.index,
    required this.layout,
    required this.showSeconds,
    required this.onChanged,
  });

  final int index;
  final BarLayout layout;
  final bool showSeconds;
  final ValueChanged<BarLayout>? onChanged;

  List<(String, IconData, VoidCallback?)> _actions(int position) {
    final groups = layout.groups;
    final pills = groups[index];
    final id = pills[position];
    final last = index == groups.length - 1;
    void set(BarLayout next) => onChanged?.call(next);
    return [
      (
        'Move left',
        Icons.arrow_back_rounded,
        position > 0
            ? () => set(layout.movePill(id, index, position - 1))
            : index > 0
            ? () => set(layout.movePill(id, index - 1))
            : null,
      ),
      (
        'Move right',
        Icons.arrow_forward_rounded,
        position < pills.length - 1
            ? () => set(layout.movePill(id, index, position + 1))
            : !last
            ? () => set(layout.movePill(id, index + 1, 0))
            : null,
      ),
      for (var i = 0; i < groups.length; i++)
        if (i != index)
          (
            'Move to group ${i + 1}',
            Icons.move_down_rounded,
            () => set(layout.movePill(id, i)),
          ),
      (
        'Move to new group',
        Icons.add_rounded,
        last && pills.length == 1
            ? null
            : () => set(layout.movePill(id, groups.length)),
      ),
      (
        id == 'sidebar' ? 'Quick settings stays visible' : 'Hide',
        Icons.visibility_off_rounded,
        id == 'sidebar' ? null : () => set(layout.hidePill(id)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pills = layout.groups[index];
    final enabled = onChanged != null;
    final centered = layout.center == index;
    final hasSidebar = pills.contains('sidebar');
    // Index after the dragged pill leaves this group.
    int target(String id, int position) {
      final from = pills.indexOf(id);
      return from >= 0 && from < position ? position - 1 : position;
    }

    return _DropArea(
      enabled: enabled,
      accepts: (_) => true,
      onDrop: (id) => onChanged!(layout.movePill(id, index)),
      builder: (active) => _GroupFrame(
        active: active,
        header: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              enabled: enabled,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const .all(4),
                  child: Icon(Icons.drag_indicator_rounded, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                centered
                    ? 'Group ${index + 1}, centered'
                    : 'Group ${index + 1}',
                style: text.labelLarge,
              ),
            ),
            IconButton(
              isSelected: centered,
              tooltip: centered ? 'Stop centering' : 'Center on bar',
              onPressed: enabled
                  ? () => onChanged!(layout.withCenter(centered ? null : index))
                  : null,
              icon: const Icon(Icons.format_align_center_rounded),
            ),
            IconButton(
              tooltip: hasSidebar
                  ? 'Quick settings must stay visible'
                  : 'Remove group',
              onPressed: enabled && !hasSidebar
                  ? () => onChanged!(layout.removeGroup(index))
                  : null,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        child: Wrap(
          spacing: 2,
          runSpacing: 8,
          children: [
            for (var j = 0; j < pills.length; j++)
              _DropArea(
                enabled: enabled,
                accepts: (_) => true,
                onDrop: (id) {
                  if (id != pills[j]) {
                    onChanged!(layout.movePill(id, index, target(id, j)));
                  }
                },
                builder: (active) => _InsertionMark(
                  active: active,
                  child: _Pill(
                    id: pills[j],
                    layout: layout,
                    showSeconds: showSeconds,
                    enabled: enabled,
                    actions: _actions(j),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A dashed drop zone that turns a dropped pill into a new last group.
class _NewGroupTarget extends StatelessWidget {
  const _NewGroupTarget({required this.enabled, required this.onDrop});

  final bool enabled;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _DropArea(
      enabled: enabled,
      accepts: (_) => true,
      onDrop: onDrop,
      builder: (active) => DecoratedBox(
        decoration: ShapeDecoration(
          color: active ? colors.primaryContainer : null,
          shape: RoundedRectangleBorder(
            borderRadius: .circular(16),
            side: BorderSide(
              color: active ? colors.primary : colors.outline,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
        ),
        child: Padding(
          padding: const .all(16),
          child: Row(
            mainAxisAlignment: .center,
            spacing: 8,
            children: [
              Icon(Icons.add_rounded, color: colors.primary),
              Text(
                'Drop a pill here to add a group',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupFrame extends StatelessWidget {
  const _GroupFrame({
    required this.header,
    required this.child,
    required this.active,
    this.outlined = false,
  });

  final Widget header;
  final Widget child;
  final bool active;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: ShapeDecoration(
        color: active
            ? colors.secondaryContainer
            : outlined
            ? null
            : colors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(16),
          side: outlined && !active
              ? BorderSide(color: colors.outlineVariant)
              : BorderSide.none,
        ),
      ),
      padding: const .all(12),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [header, child],
      ),
    );
  }
}

/// Shows where a dropped pill will be inserted, before this pill.
class _InsertionMark extends StatelessWidget {
  const _InsertionMark({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: active ? 4 : 0,
        height: 40,
        margin: .only(right: active ? 4 : 0),
        decoration: ShapeDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: const StadiumBorder(),
        ),
      ),
      child,
    ],
  );
}

class _DropArea extends StatelessWidget {
  const _DropArea({
    required this.enabled,
    required this.accepts,
    required this.onDrop,
    required this.builder,
  });

  final bool enabled;
  final bool Function(String id) accepts;
  final ValueChanged<String> onDrop;
  final Widget Function(bool active) builder;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => enabled && accepts(details.data),
    onAcceptWithDetails: (details) => onDrop(details.data),
    builder: (context, candidates, _) => builder(candidates.isNotEmpty),
  );
}

class _BarPreview extends StatelessWidget {
  const _BarPreview({required this.layout, required this.showSeconds});

  final BarLayout layout;
  final bool showSeconds;

  Widget _group(List<String> ids) => Row(
    mainAxisSize: .min,
    spacing: 8,
    children: [
      for (final id in ids)
        BarPillSample(id: id, layout: layout, showSeconds: showSeconds),
    ],
  );

  Widget _side(List<List<String>> groups, MainAxisAlignment single) => Row(
    mainAxisAlignment: groups.length == 1 ? single : .spaceBetween,
    children: [for (final ids in groups) _group(ids)],
  );

  @override
  Widget build(BuildContext context) {
    final groups = layout.groups;
    final center = layout.center;
    return ExcludeSemantics(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: .circular(20),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const .symmetric(horizontal: 16),
            child: FittedBox(
              fit: .scaleDown,
              child: SizedBox(
                // Keep the preview's spacing proportional to a wide bar.
                width: 1100,
                child: center == null
                    ? _side(groups, groups.length == 1 ? .center : .start)
                    : Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: _side(groups.sublist(0, center), .start),
                          ),
                          _group(groups[center]),
                          Expanded(
                            child: _side(groups.sublist(center + 1), .end),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.id,
    required this.layout,
    required this.showSeconds,
    required this.enabled,
    required this.actions,
  });

  final String id;
  final BarLayout layout;
  final bool showSeconds;
  final bool enabled;
  final List<(String, IconData, VoidCallback?)> actions;

  @override
  Widget build(BuildContext context) {
    final sample = BarPillSample(
      id: id,
      layout: layout,
      showSeconds: showSeconds,
    );
    return MenuAnchor(
      menuChildren: [
        for (final (label, icon, action) in actions)
          MenuItemButton(
            leadingIcon: Icon(icon),
            onPressed: action,
            child: Text(label),
          ),
      ],
      builder: (context, menu, _) => Draggable<String>(
        data: id,
        maxSimultaneousDrags: enabled ? 1 : 0,
        feedback: Material(
          type: .transparency,
          child: Opacity(opacity: .9, child: sample),
        ),
        childWhenDragging: Opacity(opacity: .3, child: _label(context, sample)),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
          child: Semantics(
            button: true,
            label: '${barPillNames[id]}, actions',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: .circular(12),
              onTap: enabled
                  ? () => menu.isOpen ? menu.close() : menu.open()
                  : null,
              child: _label(context, sample),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, Widget sample) => Padding(
    padding: const .all(6),
    child: Column(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        sample,
        Text(barPillNames[id]!, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

/// A static, illustrative miniature of one bar pill. It never shows live data.
class BarPillSample extends StatelessWidget {
  const BarPillSample({
    super.key,
    required this.id,
    required this.layout,
    required this.showSeconds,
  });

  final String id;
  final BarLayout layout;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget pill(List<Widget> children, {Color? color, Color? foreground}) =>
        Material(
          color: color ?? colors.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: IconTheme.merge(
            data: IconThemeData(size: 16, color: foreground ?? colors.primary),
            child: DefaultTextStyle.merge(
              style: text.labelMedium?.copyWith(
                color: foreground ?? colors.onSurface,
              ),
              child: SizedBox(
                height: 28,
                child: Padding(
                  padding: const .symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
    return switch (id) {
      'window' => SizedBox(
        height: 28,
        child: Column(
          mainAxisAlignment: .center,
          crossAxisAlignment: .start,
          children: [
            if (layout.windowAppName)
              Text(
                'app',
                style: text.labelSmall?.copyWith(
                  fontSize: 9,
                  height: 1,
                  color: colors.secondary,
                ),
              ),
            Text(
              'Window title',
              style: text.labelMedium?.copyWith(
                height: 1,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
      'resources' => pill([
        for (final metric in layout.resources)
          Icon(switch (metric) {
            'cpu' => Icons.memory_rounded,
            'memory' => Icons.storage_rounded,
            'gpu' => Icons.developer_board_rounded,
            _ => Icons.swap_vert_rounded,
          }),
      ]),
      'media' => pill([
        const Icon(Icons.music_note_rounded),
        const Text('Media'),
      ]),
      'workspaces' => pill([
        for (var i = 0; i < layout.workspaceCount; i++)
          Container(
            width: i == 0 ? 16 : 8,
            height: 8,
            decoration: ShapeDecoration(
              color: i == 0 ? colors.primary : colors.outlineVariant,
              shape: const StadiumBorder(),
            ),
          ),
      ]),
      'clock' => pill([
        Text.rich(
          TextSpan(
            text: 'HH:MM',
            children: [if (showSeconds) const TextSpan(text: ':SS')],
          ),
          style: TextStyle(color: colors.primary),
        ),
      ]),
      'tray' => pill([
        for (final icon in [
          Icons.chat_bubble_rounded,
          Icons.cloud_rounded,
          Icons.apps_rounded,
        ])
          Icon(icon, color: colors.onSurfaceVariant),
      ]),
      'ai-usage' => pill([const Icon(Icons.auto_awesome_rounded)]),
      'battery' => pill([const Icon(Icons.battery_std_rounded)]),
      'notifications' => pill([const Icon(Icons.notifications_rounded)]),
      _ => pill([
        const Icon(Icons.wifi_rounded),
        const Icon(Icons.bluetooth_rounded),
        const Icon(Icons.volume_up_rounded),
      ], foreground: colors.onSurface),
    };
  }
}
