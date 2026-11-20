part of 'tasks_block.dart';

class _TaskIcon extends StatelessWidget {
  const _TaskIcon(this.name, this.size);

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/tasks/$name.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
      .srcIn,
    ),
  );
}

class _TaskSupporting extends StatelessWidget {
  const _TaskSupporting(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 18 / 13,
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const .fromLTRB(12, 12, 12, 4),
      child: _TaskSupporting(label),
    ),
  );
}

class _TasksMenu extends StatelessWidget {
  const _TasksMenu({
    required this.tooltip,
    required this.items,
    this.icon = 'more',
  });

  final String tooltip;
  final String icon;
  final List<({String label, VoidCallback? action})> items;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: 180, maxWidth: 264),
    icon: _TaskIcon(icon, 20),
    onSelected: (index) => items[index].action?.call(),
    itemBuilder: (_) => [
      for (var index = 0; index < items.length; index++)
        PopupMenuItem(
          value: index,
          enabled: items[index].action != null,
          child: Text(items[index].label),
        ),
    ],
  );
}

class _ListChoiceButton extends StatelessWidget {
  const _ListChoiceButton({
    required this.label,
    required this.onPressed,
    this.count,
    this.icon = 'list',
  });

  final String label;
  final String icon;
  final int? count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: colors.surfaceContainerHighest,
        foregroundColor: colors.onSurface,
        minimumSize: const Size.fromHeight(44),
        padding: const .symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(borderRadius: .all(.circular(12))),
      ),
      onPressed: onPressed,
      child: Row(
        spacing: 8,
        children: [
          _TaskIcon(icon, 20),
          Expanded(child: Text(label, maxLines: 2, overflow: .ellipsis)),
          if (count != null)
            Semantics(
              label: '$count incomplete tasks',
              excludeSemantics: true,
              child: _TaskSupporting('$count'),
            ),
          const _TaskIcon('expand', 20),
        ],
      ),
    );
  }
}

InputDecoration _taskInput(
  BuildContext context, {
  String? hint,
  String? label,
  String? error,
  Widget? icon,
  Widget? action,
  double radius = 12,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    filled: true,
    fillColor: colors.surfaceContainerHighest,
    labelText: label,
    hintText: hint,
    errorText: error,
    errorMaxLines: 3,
    prefixIcon: icon,
    suffixIcon: action,
    border: OutlineInputBorder(
      borderSide: .none,
      borderRadius: .circular(radius),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colors.primary, width: 2),
      borderRadius: .circular(radius),
    ),
    contentPadding: const .symmetric(horizontal: 16, vertical: 12),
  );
}

Widget? _lengthCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => maxLength != null && currentLength >= maxLength - 80
    ? _TaskSupporting('$currentLength / $maxLength')
    : null;

String _friendlyDate(BuildContext context, DateTime date, DateTime today) {
  if (DateUtils.isSameDay(date, today)) return 'Today';
  if (DateUtils.isSameDay(date, DateUtils.addDaysToDate(today, 1))) {
    return 'Tomorrow';
  }
  final local = MaterialLocalizations.of(context);
  return date.year == today.year
      ? local.formatMediumDate(date)
      : local.formatShortDate(date);
}

String _actionError(Object error) => error is TasksEditException
    ? error.message
    : 'Couldn’t complete this change. Try again.';

class _QuickAdd extends StatelessWidget {
  const _QuickAdd({
    required this.controller,
    this.focusNode,
    required this.label,
    required this.saving,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool saving;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    readOnly: saving,
    maxLength: 1024,
    buildCounter: _lengthCounter,
    textInputAction: .done,
    decoration: _taskInput(
      context,
      hint: label,
      icon: const Center(widthFactor: 1, child: _TaskIcon('add', 20)),
      action: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => controller.text.trim().isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Add task',
                onPressed: saving ? null : onSubmitted,
                icon: const _TaskIcon('add', 20),
              ),
      ),
      radius: 16,
    ),
    onSubmitted: (_) => onSubmitted(),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: _taskInput(
      context,
      hint: hint,
      icon: const Icon(Icons.search_rounded, size: 20),
      action: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const _TaskIcon('close', 20),
              onPressed: () {
                controller.clear();
                onChanged();
              },
            ),
    ),
    onChanged: (_) => onChanged(),
  );
}

class _TaskPrompt extends StatelessWidget {
  const _TaskPrompt({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onPressed,
    this.loading = false,
  });

  final String icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const .symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 12,
          mainAxisSize: .min,
          children: [
            _TaskIcon(icon, 40),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w600),
            ),
            if (message != null) Text(message!),
            if (action != null)
              FilledButton(onPressed: onPressed, child: Text(action!)),
            if (loading)
              for (final height in [40.0, 32.0, 40.0])
                ExcludeSemantics(
                  child: Container(
                    width: double.infinity,
                    height: height,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: .circular(12),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TaskBanner extends StatelessWidget {
  const _TaskBanner({
    this.icon,
    required this.title,
    this.detail,
    required this.action,
    required this.onPressed,
  });

  final String? icon;
  final String title;
  final String? detail;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: .circular(16),
        ),
        child: Padding(
          padding: const .fromLTRB(12, 4, 6, 4),
          child: Row(
            spacing: 8,
            children: [
              if (icon != null) _TaskIcon(icon!, 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                    if (detail != null)
                      _TaskSupporting(
                        detail!,
                        color: colors.onSecondaryContainer,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSecondaryContainer,
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TaskAction {
  edit('Edit'),
  addChild('Add subtask'),
  move('Move task…'),
  moveOut('Move out of parent'),
  up('Move up'),
  down('Move down'),
  source('Open source'),
  external('Open in Google Tasks'),
  delete('Delete task…'),
  issues('Review sync issue');

  const _TaskAction(this.label);
  final String label;
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.childRow,
    required this.dateLabel,
    required this.listLabel,
    required this.children,
    required this.expanded,
    required this.onExpand,
    required this.onOpen,
    required this.onComplete,
    required this.onAction,
    required this.moveEarlier,
    required this.moveLater,
    required this.canDrag,
    required this.acceptsDrag,
    required this.onDrop,
  });

  final GoogleTask task;
  final bool childRow;
  final String? dateLabel;
  final String? listLabel;
  final List<GoogleTask> children;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onOpen;
  final ValueChanged<bool>? onComplete;
  final ValueChanged<_TaskAction> onAction;
  final bool moveEarlier;
  final bool moveLater;
  final bool canDrag;
  final bool Function(_TaskKey) acceptsDrag;
  final ValueChanged<_TaskKey> onDrop;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final children = widget.children;
    final detail = [
      ?widget.dateLabel,
      ?widget.listLabel,
      if (children.isNotEmpty)
        '${children.where((task) => task.completed).length}/${children.length} subtasks',
      if (task.assigned)
        switch (task.sourceKind) {
          'DOCUMENT' => 'Google Docs',
          'SPACE' => 'Google Chat',
          _ => 'Assigned',
        },
      if (task.error != null)
        'Couldn’t sync'
      else if (task.pending)
        'Waiting to sync',
      if (task.notes.isNotEmpty && widget.dateLabel == null && !widget.childRow)
        task.notes.replaceAll('\n', ' '),
    ].join(' · ');
    final menu = [
      _TaskAction.edit,
      if (!task.assigned && !task.hidden && !widget.childRow)
        _TaskAction.addChild,
      if (!task.pending) _TaskAction.move,
      if (!task.pending && task.parent != null) _TaskAction.moveOut,
      if (widget.moveEarlier) _TaskAction.up,
      if (widget.moveLater) _TaskAction.down,
      if (task.sourceLink != null) _TaskAction.source,
      _TaskAction.external,
      if (!task.pending) _TaskAction.delete,
      if (task.error != null) _TaskAction.issues,
    ];

    return Padding(
      padding: .only(left: widget.childRow ? 24 : 0, bottom: 2),
      child: DragTarget<_TaskKey>(
        onWillAcceptWithDetails: (details) => widget.acceptsDrag(details.data),
        onAcceptWithDetails: (details) => widget.onDrop(details.data),
        builder: (context, candidates, rejected) => Material(
          shape: RoundedRectangleBorder(
            borderRadius: .circular(16),
            side: _focused || candidates.isNotEmpty
                ? BorderSide(color: colors.primary, width: 2)
                : .none,
          ),
          color: task.error == null
              ? Colors.transparent
              : colors.errorContainer,
          clipBehavior: .antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: detail.isEmpty ? 48 : 64),
            child: InkWell(
              onTap: widget.onOpen,
              onFocusChange: (focused) => setState(() => _focused = focused),
              borderRadius: .circular(16),
              hoverColor: colors.surfaceContainerHighest,
              child: Row(
                children: [
                  if (widget.canDrag)
                    LongPressDraggable<_TaskKey>(
                      data: _key(task),
                      feedback: Material(
                        color: colors.secondaryContainer,
                        borderRadius: .circular(16),
                        child: Padding(
                          padding: const .all(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(task.title, overflow: .ellipsis),
                          ),
                        ),
                      ),
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: .only(left: 4),
                          child: Icon(Icons.drag_indicator_rounded, size: 16),
                        ),
                      ),
                    ),
                  Semantics(
                    label: task.completed
                        ? 'Mark ${task.title} incomplete'
                        : 'Complete ${task.title}',
                    child: SizedBox.square(
                      dimension: 44,
                      child: Checkbox(
                        value: task.completed,
                        onChanged: widget.onComplete == null
                            ? null
                            : (value) =>
                                  widget.onComplete?.call(value ?? false),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const .symmetric(vertical: 8, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: .ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 16,
                              height: 22 / 16,
                              decoration: task.completed ? .lineThrough : null,
                              color: task.error != null
                                  ? colors.onErrorContainer
                                  : task.completed
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                            ),
                          ),
                          if (detail.isNotEmpty)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: .ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: task.error == null
                                    ? colors.onSurfaceVariant
                                    : colors.onErrorContainer,
                                fontSize: 13,
                                height: 18 / 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (children.isNotEmpty)
                    IconButton(
                      tooltip: widget.expanded
                          ? 'Collapse subtasks'
                          : 'Expand subtasks',
                      onPressed: widget.onExpand,
                      icon: RotatedBox(
                        quarterTurns: widget.expanded ? 2 : 0,
                        child: const _TaskIcon('expand', 20),
                      ),
                    ),
                  _TasksMenu(
                    tooltip: 'Task menu for ${task.title}',
                    items: [
                      for (final action in menu)
                        (
                          label: action.label,
                          action: () => widget.onAction(action),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
