part of 'tasks_block.dart';

class _TasksHeader extends StatelessWidget {
  const _TasksHeader({
    this.listMenu,
    required this.syncing,
    this.onSync,
    required this.onSettings,
    this.onSearch,
    required this.showingSearch,
    this.onClose,
  });

  final Widget? listMenu;
  final bool syncing;
  final VoidCallback? onSync;
  final VoidCallback onSettings;
  final VoidCallback? onSearch;
  final bool showingSearch;
  final VoidCallback? onClose;

  static final _actionStyle = IconButton.styleFrom(
    fixedSize: const Size.square(40),
    minimumSize: const Size.square(40),
    tapTargetSize: .shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      'Tasks',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: .w700,
        color: theme.brightness == .dark
            ? theme.colorScheme.primaryFixed
            : theme.colorScheme.onPrimaryFixedVariant,
        height: 30 / 24,
        leadingDistribution: .even,
      ),
    );
    final actions = [
      if (onSearch != null)
        IconButton(
          tooltip: showingSearch ? 'Hide search' : 'Search tasks',
          style: _actionStyle,
          onPressed: onSearch,
          icon: Icon(
            showingSearch ? Icons.search_off_rounded : Icons.search_rounded,
            size: 20,
          ),
        ),
      IconButton.filledTonal(
        tooltip: syncing ? 'Syncing tasks' : 'Sync now',
        style: _actionStyle,
        onPressed: syncing ? null : onSync,
        icon: syncing
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
      ),
      IconButton.filledTonal(
        tooltip: 'Task settings',
        style: _actionStyle,
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined, size: 20),
      ),
      if (onClose != null)
        IconButton(
          tooltip: 'Close',
          style: _actionStyle,
          onPressed: onClose,
          icon: const _TaskIcon('close', 20),
        ),
    ];
    final menu = listMenu;
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = actions.length * (40 + 8);
        final inlineList =
            (constraints.maxWidth - actionWidth) /
                MediaQuery.textScalerOf(context).scale(1) >=
            240;
        if (!inlineList && menu != null) {
          return Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Row(
                spacing: 8,
                children: [
                  Expanded(child: title),
                  ...actions,
                ],
              ),
              menu,
            ],
          );
        }
        return Row(
          spacing: 8,
          children: [
            if (menu == null)
              Expanded(child: title)
            else ...[
              title,
              Expanded(
                child: Align(alignment: .centerLeft, child: menu),
              ),
            ],
            ...actions,
          ],
        );
      },
    );
  }
}

ButtonStyle _taskTextButtonStyle(BuildContext context) => TextButton.styleFrom(
  minimumSize: const Size(0, 32),
  visualDensity: .standard,
  textStyle: Theme.of(context).textTheme.labelLarge
      ?.copyWith(fontSize: 13, height: 18 / 13),
  padding: const .symmetric(horizontal: 8, vertical: 4),
  tapTargetSize: .shrinkWrap,
);

class _CompletedControl extends StatelessWidget {
  const _CompletedControl({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: 12),
    child: Align(
      alignment: .centerLeft,
      child: Semantics(
        expanded: expanded,
        child: TextButton.icon(
          style: _taskTextButtonStyle(context).copyWith(
            foregroundColor: .all(Theme.of(context).colorScheme.onSurface),
          ),
          icon: RotatedBox(
            quarterTurns: expanded ? 2 : 0,
            child: const _TaskIcon('expand-small', 18),
          ),
          onPressed: onToggle,
          label: const Text('Completed'),
        ),
      ),
    ),
  );
}

class _TasksFooter extends StatelessWidget {
  const _TasksFooter({
    this.error,
    this.notice,
    this.onShowAll,
    this.onAdd,
    this.syncLabel,
  });

  final Widget? error;
  final Widget? notice;
  final VoidCallback? onShowAll;
  final VoidCallback? onAdd;
  final String? syncLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        ?error,
        ?notice,
        if (onShowAll != null || onAdd != null)
          Wrap(
            alignment: onShowAll == null || onAdd == null
                ? .end
                : .spaceBetween,
            crossAxisAlignment: .center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onShowAll != null)
                TextButton(
                  style: _taskTextButtonStyle(context),
                  onPressed: onShowAll,
                  child: const Text('View all'),
                ),
              if (onAdd != null)
                FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Add task (N)',
                  onPressed: onAdd,
                  child: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        if (syncLabel case final label?)
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _FullTasksLayout extends StatelessWidget {
  const _FullTasksLayout({
    required this.header,
    required this.list,
    required this.hasTaskRows,
    required this.footer,
  });

  final Widget header;
  final Widget list;
  final bool hasTaskRows;
  final Widget footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      if (constraints.maxHeight <
          520 + (MediaQuery.textScalerOf(context).scale(16) - 16) * 16) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              header,
              if (hasTaskRows) SizedBox(height: 200, child: list) else list,
              footer,
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          header,
          Flexible(
            child: hasTaskRows ? list : SingleChildScrollView(child: list),
          ),
          footer,
        ],
      );
    },
  );
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog({required this.store, required this.list});

  final TasksStore store;
  final TaskList list;

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _title = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final task = await widget.store.addTask(widget.list.id, title);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, task);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _actionError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _TasksDialog(
    title: 'Add task',
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        _QuickAdd(
          controller: _title,
          autofocus: true,
          label: 'Add a task to ${widget.list.title}',
          saving: _saving,
          onSubmitted: _submit,
        ),
        if (_error case final error?)
          Semantics(
            liveRegion: true,
            child: _TaskSupporting(
              error,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    ),
  );
}

class _ListSelectMenu extends StatelessWidget {
  const _ListSelectMenu({
    required this.label,
    required this.count,
    required this.selectedId,
    required this.lists,
    required this.onSelected,
    required this.onManage,
    this.sortLabel,
    required this.onSort,
    this.archived,
  });

  final String label;
  final int count;
  final String? selectedId;
  final List<TaskList> lists;
  final ValueChanged<String?> onSelected;
  final VoidCallback onManage;
  final String? sortLabel;
  final VoidCallback onSort;
  final ({bool showing, VoidCallback toggle})? archived;

  @override
  Widget build(BuildContext context) {
    Widget check(bool selected) => selected
        ? const Icon(Icons.check_rounded, size: 18)
        : const SizedBox.square(dimension: 18);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(180, 0)),
        maximumSize: WidgetStatePropertyAll(Size(264, 320)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: check(selectedId == null),
          onPressed: () => onSelected(null),
          child: const Text('All lists'),
        ),
        for (final list in lists)
          MenuItemButton(
            leadingIcon: check(selectedId == list.id),
            onPressed: () => onSelected(list.id),
            child: Text(list.title, maxLines: 1, overflow: .ellipsis),
          ),
        const Divider(),
        if (sortLabel case final label?)
          MenuItemButton(
            leadingIcon: const Icon(Icons.sort_rounded, size: 18),
            onPressed: onSort,
            child: Text(label),
          ),
        if (archived case final archive?)
          MenuItemButton(
            leadingIcon: Icon(
              archive.showing ? Icons.archive_rounded : Icons.archive_outlined,
              size: 18,
            ),
            onPressed: archive.toggle,
            child: Text(
              archive.showing ? 'Hide archived tasks' : 'Show archived tasks',
            ),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_note_rounded, size: 18),
          onPressed: onManage,
          child: const Text('Manage lists'),
        ),
      ],
      builder: (context, controller, _) => _ListChoiceButton(
        label: label,
        count: count,
        maxLines: 1,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _ListChoiceButton extends StatelessWidget {
  const _ListChoiceButton({
    required this.label,
    required this.onPressed,
    this.count,
    this.icon = 'list',
    this.maxLines = 2,
  });

  final String label;
  final String icon;
  final int? count;
  final int maxLines;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: colors.surfaceContainerHighest,
        foregroundColor: colors.onSurface,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          height: 20 / 14,
        ),
        minimumSize: const Size(0, 32),
        visualDensity: .standard,
        padding: const .fromLTRB(10, 4, 8, 4),
        tapTargetSize: .shrinkWrap,
        shape: const StadiumBorder(),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          _TaskIcon(icon, 18),
          Flexible(
            child: Text(label, maxLines: maxLines, overflow: .ellipsis),
          ),
          if (count != null)
            Semantics(
              label: '$count incomplete tasks',
              excludeSemantics: true,
              child: _TaskSupporting('$count', color: colors.primary),
            ),
          const _TaskIcon('expand-small', 18),
        ],
      ),
    );
  }
}

class _ViewFilters extends StatelessWidget {
  const _ViewFilters({required this.selected, required this.onSelected});

  final _View selected;
  final ValueChanged<_View> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SegmentedButton<_View>(
      expandedInsets: .zero,
      showSelectedIcon: false,
      selected: {selected},
      onSelectionChanged: (views) => onSelected(views.single),
      style: SegmentedButton.styleFrom(
        side: .none,
        foregroundColor: colors.onSurfaceVariant,
        selectedForegroundColor: colors.onPrimary,
        backgroundColor: Colors.transparent,
        selectedBackgroundColor: Colors.transparent,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: .w400,
          letterSpacing: 0,
        ),
        shape: const StadiumBorder(),
        padding: .zero,
        visualDensity: .standard,
        tapTargetSize: .shrinkWrap,
      ),
      segments: [
        for (final view in _View.values)
          ButtonSegment(
            value: view,
            label: Padding(
              padding: .fromSTEB(
                view == .today ? 0 : 1,
                0,
                view == .all ? 0 : 1,
                0,
              ),
              child: Ink(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: selected == view
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: .circular(
                      selected == view || view == .today ? 20 : 6,
                    ),
                    end: .circular(selected == view || view == .all ? 20 : 6),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const .symmetric(horizontal: 4, vertical: 8),
                    child: Center(child: Text(view.label, textAlign: .center)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

_Group _taskGroup(DateTime? date, DateTime now) {
  if (date == null) return .unscheduled;
  final day = DateUtils.dateOnly(date);
  if (day == now) return .today;
  return day.isBefore(now) ? .earlier : .upcoming;
}

List<Object> _taskRows(
  List<GoogleTask> parents,
  Map<_TaskKey, List<GoogleTask>> children,
  DateTime now, {
  required bool groupByDate,
  required Set<_TaskKey> opened,
}) {
  final rows = <Object>[];
  _Group? previous;
  for (final task in parents) {
    if (groupByDate) {
      final group = _taskGroup(task.scheduled, now);
      if (group != previous) rows.add(group);
      previous = group;
    }
    final remaining = [task];
    while (remaining.isNotEmpty) {
      final row = remaining.removeLast();
      rows.add(row);
      if (opened.contains(_key(row))) {
        final subtasks = children[_key(row)];
        if (subtasks != null) remaining.addAll(subtasks.reversed);
      }
    }
  }
  return rows;
}
