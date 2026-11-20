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
  const _TasksMenu({required this.tooltip, required this.items});

  final String tooltip;
  final List<({String label, VoidCallback? action})> items;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 4),
    style: const MenuStyle(
      minimumSize: WidgetStatePropertyAll(Size(180, 0)),
      maximumSize: WidgetStatePropertyAll(Size(264, 320)),
    ),
    menuChildren: [
      for (final item in items)
        MenuItemButton(
          onPressed: item.action,
          child: Text(item.label, maxLines: 2, overflow: .ellipsis),
        ),
    ],
    builder: (context, controller, _) => IconButton(
      tooltip: tooltip,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const _TaskIcon('more', 20),
    ),
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.remaining, required this.completed});

  final int remaining;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = remaining + completed;
    final progress = completed / total;
    final percent = '${(progress * 100).round()}%';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: .circular(28),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 18),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onPrimaryContainer),
          child: Column(
            spacing: 16,
            crossAxisAlignment: .stretch,
            children: [
              Row(
                spacing: 12,
                children: [
                  Text(
                    '$remaining',
                    style: TextStyle(
                      fontSize: remaining < 100 ? 56 : 32,
                      height: 60 / 56,
                      fontWeight: .w500,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        const Text(
                          'left for today',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '$completed of $total done',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(percent, style: const TextStyle(fontSize: 16)),
                ],
              ),
              LinearProgressIndicator(
                // The current Material appearance adds the track gap and stop.
                // ignore: deprecated_member_use
                year2023: false,
                value: progress,
                semanticsLabel: 'Today’s task progress',
                semanticsValue: percent,
                minHeight: 8,
                borderRadius: .circular(4),
                trackGap: 4,
                stopIndicatorRadius: 2,
                color: colors.primary,
                stopIndicatorColor: colors.primary,
                backgroundColor: colors.onPrimary,
              ),
            ],
          ),
        ),
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
    this.autofocus = false,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool saving;
  final bool autofocus;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    readOnly: saving,
    maxLength: 1024,
    buildCounter: _lengthCounter,
    textInputAction: .done,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 15, height: 20 / 15),
    decoration: _taskInput(
      context,
      hint: label,
      icon: Center(
        widthFactor: 1,
        child: IconTheme(
          data: IconThemeData(color: Theme.of(context).colorScheme.primary),
          child: const _TaskIcon('add', 20),
        ),
      ),
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
      radius: 24,
    ),
    onSubmitted: (_) => onSubmitted(),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
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
    this.corners,
    this.hasNextTask = false,
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
  final BorderRadius? corners;
  final bool hasNextTask;
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
  bool _focusWithin = false;
  bool _hovered = false;

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

    final corners = widget.corners ?? BorderRadius.circular(16);
    final row = Padding(
      padding: .only(bottom: widget.hasNextTask ? 2 : 0),
      child: DragTarget<_TaskKey>(
        onWillAcceptWithDetails: (details) => widget.acceptsDrag(details.data),
        onAcceptWithDetails: (details) => widget.onDrop(details.data),
        builder: (context, candidates, rejected) => Material(
          shape: RoundedRectangleBorder(
            borderRadius: corners,
            side: _focused || candidates.isNotEmpty
                ? BorderSide(color: colors.primary, width: 2)
                : .none,
          ),
          color: task.error != null
              ? colors.errorContainer
              : widget.corners == null
              ? Colors.transparent
              : colors.surfaceContainerHigh,
          clipBehavior: .antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: detail.isEmpty ? 48 : 64),
            child: InkWell(
              onTap: widget.onOpen,
              onFocusChange: (focused) => setState(() => _focused = focused),
              borderRadius: corners,
              hoverColor: task.error == null
                  ? colors.surfaceContainerHighest
                  : null,
              child: Row(
                children: [
                  if (widget.childRow) const SizedBox(width: 24),
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
                      dimension: 48,
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
                      padding: const .fromLTRB(0, 8, 8, 8),
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
                  Opacity(
                    alwaysIncludeSemantics: true,
                    opacity: widget.corners == null || _hovered || _focusWithin
                        ? 1
                        : 0,
                    child: _TasksMenu(
                      tooltip: 'Task menu for ${task.title}',
                      items: [
                        for (final action in menu)
                          (
                            label: action.label,
                            action: () => widget.onAction(action),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) => setState(() => _focusWithin = focused),
        child: row,
      ),
    );
  }
}
