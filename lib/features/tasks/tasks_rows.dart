part of 'tasks_block.dart';

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.dueLabel,
    required this.dateLabel,
    required this.first,
    required this.last,
    required this.workingOn,
    required this.showBookmark,
    required this.onBookmark,
    required this.onComplete,
    required this.onOpen,
    required this.onSource,
  });

  final GoogleTask task;
  final String dueLabel;
  final String? dateLabel;
  final bool first;
  final bool last;
  final bool workingOn;
  final bool showBookmark;
  final VoidCallback? onBookmark;
  final VoidCallback? onComplete;
  final VoidCallback? onOpen;
  final VoidCallback? onSource;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = connectedClockRowRadius(
      first: widget.first,
      last: widget.last,
    );
    final bookmark = widget.workingOn ? 'Remove from Working on' : 'Working on';
    final semanticsLabel = [
      task.title,
      'due ${widget.dueLabel}',
      task.completed ? 'done' : 'not done',
      if (widget.workingOn) 'Working on',
      if (task.assigned) 'assigned',
      if (task.syncError) 'couldn’t sync' else if (task.pending) 'pending',
    ].join(', ');
    return Padding(
      padding: .only(bottom: widget.last ? 0 : 2),
      child: MenuAnchor(
        childFocusNode: _focus,
        menuChildren: [
          MenuItemButton(
            onPressed: widget.onOpen,
            child: const Text('Open in Google Tasks'),
          ),
          if (widget.onBookmark != null)
            MenuItemButton(onPressed: widget.onBookmark, child: Text(bookmark)),
          MenuItemButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: task.title)),
            child: const Text('Copy title'),
          ),
          if (widget.onSource case final openSource?)
            MenuItemButton(
              onPressed: openSource,
              child: const Text('Open source'),
            ),
        ],
        builder: (context, menu, _) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _focus.focusInDirection(.up),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _focus.focusInDirection(.down),
            const SingleActivator(LogicalKeyboardKey.space): ?widget.onComplete,
            const SingleActivator(LogicalKeyboardKey.keyB): ?widget.onBookmark,
            const SingleActivator(LogicalKeyboardKey.enter): ?widget.onOpen,
            const SingleActivator(LogicalKeyboardKey.contextMenu): menu.open,
            const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                menu.open,
          },
          child: GestureDetector(
            behavior: .opaque,
            onSecondaryTapUp: (details) {
              _focus.requestFocus();
              menu.open(position: details.localPosition);
            },
            child: CustomPaint(
              foregroundPainter: _focused
                  ? ClockCardRowFocus(radius, colors.secondary)
                  : null,
              child: Material(
                color: widget.workingOn
                    ? colors.primaryContainer
                    : colors.surfaceContainerHigh,
                clipBehavior: .antiAlias,
                borderRadius: radius,
                child: Semantics(
                  label: semanticsLabel,
                  button: widget.onOpen != null,
                  onTap: widget.onOpen,
                  child: InkWell(
                    excludeFromSemantics: true,
                    focusNode: _focus,
                    onFocusChange: (focused) =>
                        setState(() => _focused = focused),
                    // Keep the row navigable even when Google omits its URL.
                    onTap: widget.onOpen ?? _focus.requestFocus,
                    onLongPress: menu.open,
                    borderRadius: radius,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const .only(left: 4, right: 12),
                        child: Row(
                          spacing: 4,
                          children: [
                            ExcludeFocus(
                              child: Checkbox(
                                value: task.completed,
                                semanticLabel: task.completed
                                    ? 'Mark incomplete'
                                    : 'Mark complete',
                                onChanged: widget.onComplete == null
                                    ? null
                                    : (_) => widget.onComplete!(),
                              ),
                            ),
                            Expanded(
                              child: ExcludeSemantics(
                                child: Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 22 / 16,
                                    color: widget.workingOn
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.dateLabel case final date?)
                              ExcludeSemantics(
                                child: Text(
                                  date,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 18 / 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (task.syncError || task.pending)
                              Tooltip(
                                message: task.syncError
                                    ? 'Couldn’t sync'
                                    : 'Pending',
                                excludeFromSemantics: true,
                                child: Icon(
                                  task.syncError
                                      ? Icons.error_outline
                                      : Icons.schedule_outlined,
                                  size: 16,
                                  color: task.syncError
                                      ? colors.error
                                      : widget.workingOn
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            if (widget.showBookmark)
                              ExcludeFocus(
                                child: IconButton(
                                  tooltip: bookmark,
                                  padding: .zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 44,
                                  ),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(28, 44),
                                    padding: .zero,
                                    tapTargetSize: .shrinkWrap,
                                  ),
                                  iconSize: 20,
                                  color: widget.workingOn
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                  onPressed: widget.onBookmark,
                                  icon: Icon(
                                    widget.workingOn
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                  ),
                                ),
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
        ),
      ),
    );
  }
}
