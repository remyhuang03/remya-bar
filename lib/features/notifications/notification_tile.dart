import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/percent_text.dart';
import '../../widgets/wave_progress.dart';
import 'notification_artwork.dart';
import 'notification_row_controls.dart';

export 'notification_artwork.dart' show NotificationLeading;
export 'notification_row_controls.dart' show NotificationRowControls;

typedef NotificationAction = ValueChanged<Map<String, Object?>>;

/// A history row or heads-up notification.
class NotificationTile extends StatefulWidget {
  const NotificationTile({
    super.key,
    required this.data,
    required this.onAction,
    required this.expanded,
    required this.onToggle,
    this.radius = const .all(.circular(28)),
    this.focusNode,
    this.onFocusChange,
    this.onDismissSection,
    this.showFocusIndicator = true,
    this.toast = false,
  });

  final Map data;
  final NotificationAction onAction;
  final bool expanded;
  final VoidCallback? onToggle;
  final BorderRadius radius;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onDismissSection;
  final bool showFocusIndicator;
  final bool toast;

  @override
  State<NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<NotificationTile> {
  late final _localFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _localFocus;
  bool _hovered = false;
  bool _focused = false;

  void _dismiss() => widget.onAction({
    'action': 'notification.dismiss',
    'id': widget.data['id'],
  });

  void _invoke(String action) => widget.onAction({
    'action': 'notification.invoke',
    'id': widget.data['id'],
    'key': action,
  });

  void _setHovered(bool hovered) {
    if (_hovered != hovered) setState(() => _hovered = hovered);
  }

  void _activate() {
    if (widget.data['default'] == true) {
      _invoke('default');
    } else {
      widget.onToggle?.call();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) return .ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activate();
      case LogicalKeyboardKey.space:
        widget.onToggle?.call();
      case LogicalKeyboardKey.arrowRight:
        if (!widget.expanded) widget.onToggle?.call();
      case LogicalKeyboardKey.arrowLeft:
        if (widget.expanded) widget.onToggle?.call();
      case LogicalKeyboardKey.delete:
        if (HardwareKeyboard.instance.isShiftPressed &&
            widget.onDismissSection != null) {
          widget.onDismissSection!();
        } else {
          _dismiss();
        }
      case LogicalKeyboardKey.backspace:
        _dismiss();
      default:
        return .ignored;
    }
    return .handled;
  }

  @override
  void dispose() {
    _localFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = widget.data;
    final critical = data['urgency'] == 2;
    final showFocus = _focused && widget.showFocusIndicator;
    final showDismiss = _hovered || showFocus;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final base = critical
        ? Color.alphaBlend(
            colors.error.withValues(alpha: .08),
            colors.surfaceContainerHighest,
          )
        : colors.surfaceContainerHighest;
    final background = _hovered
        ? Color.alphaBlend(colors.onSurface.withValues(alpha: .08), base)
        : base;
    final canExpand = widget.onToggle != null;
    final received = data['received'];
    final appName = ((data['appName'] as String?) ?? '').trim();
    final summary = (data['summary'] as String?) ?? '';
    final body = (data['body'] as List? ?? const []).whereType<Map>();
    final bodyText = body.map((run) => run['text'] ?? '').join();
    final actions = [
      for (final action in data['actions'] as List? ?? const [])
        if (action case [final String key, final String label]) (key, label),
    ].take(3);
    final progress = data['progress'];
    final hasImage =
        NotificationPicture.hasImage(data) &&
        (critical || data['avatar'] != true);
    final meta = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      color: colors.onSurfaceVariant,
    );
    final title = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: .w500,
      color: colors.onSurface,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      color: colors.onSurfaceVariant,
    );
    final bodyWidget = _NotificationBody(
      runs: body,
      style: bodyStyle,
      link: colors.primary,
      maxLines: widget.expanded ? (widget.toast ? 6 : null) : 1,
      onLink: (href) =>
          widget.onAction({'action': 'notification.link', 'href': href}),
    );
    final progressWidget = progress is int
        ? _NotificationProgress(value: progress, style: meta)
        : null;
    final heading = _NotificationHeading(
      label: widget.expanded
          ? appName.isEmpty
                ? 'Notification'
                : appName
          : summary,
      style: widget.expanded ? meta?.copyWith(fontWeight: .w500) : title,
      meta: meta,
      received: received,
      critical: critical,
      expanded: widget.expanded,
    );
    final hasPrimaryAction = data['default'] == true || canExpand;
    final content = Padding(
      padding: .fromLTRB(16, 16, 16, widget.expanded ? 12 : 16),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 16,
            crossAxisAlignment: .start,
            children: [
              NotificationLeading(data: data, background: background),
              Expanded(
                child: widget.expanded
                    ? Column(
                        crossAxisAlignment: .stretch,
                        mainAxisSize: .min,
                        children: [
                          SizedBox(
                            height: math.max(
                              40,
                              MediaQuery.textScalerOf(context).scale(20),
                            ),
                            child: Padding(
                              padding: .only(
                                right:
                                    (canExpand ? 44 : 0) +
                                    (showDismiss ? 34 : 0),
                              ),
                              child: heading,
                            ),
                          ),
                          if (summary.isNotEmpty)
                            ExcludeSemantics(
                              child: Text(
                                summary,
                                maxLines: widget.toast ? 1 : null,
                                overflow: widget.toast ? .ellipsis : .visible,
                                style: title,
                              ),
                            ),
                          if (bodyText.isNotEmpty)
                            Padding(
                              padding: const .only(top: 2),
                              child: bodyWidget,
                            ),
                          if (progressWidget != null)
                            Padding(
                              padding: const .only(top: 8, bottom: 2),
                              child: progressWidget,
                            ),
                          if (hasImage)
                            Padding(
                              padding: const .only(top: 10),
                              child: NotificationPicture(
                                data: data,
                                width: double.infinity,
                                height: 152,
                                radius: 16,
                              ),
                            ),
                        ],
                      )
                    : Padding(
                        padding: .only(right: canExpand ? 44 : 0),
                        child: Row(
                          spacing: 12,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: .stretch,
                                mainAxisSize: .min,
                                children: [
                                  heading,
                                  if (bodyText.isNotEmpty) bodyWidget,
                                  if (progressWidget != null)
                                    Padding(
                                      padding: const .only(top: 6),
                                      child: progressWidget,
                                    ),
                                ],
                              ),
                            ),
                            if (hasImage)
                              SizedBox(
                                width: 48,
                                height: 40,
                                child: OverflowBox(
                                  minHeight: 48,
                                  maxHeight: 48,
                                  child: NotificationPicture(
                                    data: data,
                                    width: 48,
                                    height: 48,
                                    radius: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          if (widget.expanded && actions.isNotEmpty)
            Padding(
              padding: const .only(left: 44),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (index, (key, label)) in actions.indexed)
                    _NotificationActionButton(
                      label: label,
                      prominent: critical && index == 0,
                      critical: critical,
                      onPressed: () => _invoke(key),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKeyEvent,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
        },
        descendantsAreTraversable: _focused || widget.toast,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          liveRegion: widget.toast && !MediaQuery.supportsAnnounceOf(context),
          label: notificationAccessibleName(context, data),
          onTap: hasPrimaryAction ? _activate : null,
          child: Stack(
            clipBehavior: .none,
            children: [
              Material(
                color: background,
                borderRadius: widget.radius,
                animationDuration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                clipBehavior: .antiAlias,
                // Inside the card so its shape follows the content height.
                child: AnimatedSize(
                  duration: reducedMotion
                      ? Duration.zero
                      : notificationSpatialDuration,
                  curve: notificationSpatialCurve,
                  alignment: .topCenter,
                  child: Stack(
                    children: [
                      InkWell(
                        onTap: hasPrimaryAction ? _activate : null,
                        onTertiaryTapUp: (_) => _dismiss(),
                        canRequestFocus: false,
                        excludeFromSemantics: true,
                        hoverColor: Colors.transparent,
                        child: content,
                      ),
                      if (canExpand || showDismiss)
                        Positioned(
                          right: 16,
                          top: widget.expanded ? 12 : 2,
                          child: NotificationRowControls(
                            expanded: widget.expanded,
                            onToggle: widget.onToggle,
                            onDismiss: _dismiss,
                            showDismiss: showDismiss,
                            hitHeight: 48,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showFocus)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      foregroundPainter: _FocusOutline(
                        borderRadius: widget.radius,
                        color: colors.secondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusOutline extends CustomPainter {
  const _FocusOutline({required this.borderRadius, required this.color});

  final BorderRadius borderRadius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    borderRadius.toRRect(Offset.zero & size).inflate(3.5),
    Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = .stroke,
  );

  @override
  bool shouldRepaint(_FocusOutline oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}

class _NotificationHeading extends StatelessWidget {
  const _NotificationHeading({
    required this.label,
    required this.style,
    required this.meta,
    required this.received,
    required this.critical,
    required this.expanded,
  });

  final String label;
  final TextStyle? style;
  final TextStyle? meta;
  final Object? received;
  final bool critical;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Row(
            spacing: width >= 48 ? 4 : 0,
            children: [
              if (label.isNotEmpty)
                Flexible(
                  child: ConstrainedBox(
                    constraints: .new(maxWidth: expanded ? 150 : 170),
                    child: Text(
                      label,
                      style: style,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                ),
              if (received is int) ...[
                if (label.isNotEmpty && width >= 48) Text('·', style: meta),
                ConstrainedBox(
                  constraints: .new(maxWidth: width * (critical ? .35 : .45)),
                  child: NotificationTime(received: received, style: meta),
                ),
              ],
              if (critical)
                Container(
                  constraints: .new(maxWidth: width * .45),
                  padding: const .symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: .circular(6),
                  ),
                  child: Text(
                    'Critical',
                    style: meta?.copyWith(
                      color: colors.onErrorContainer,
                      fontSize: 11,
                      height: 16 / 11,
                      fontWeight: .w500,
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationProgress extends StatelessWidget {
  const _NotificationProgress({required this.value, required this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Progress $value%',
      excludeSemantics: true,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: SizedBox(
              height: 12,
              child: CustomPaint(
                painter: WaveProgressPainter(
                  fraction: value / 100,
                  active: colors.primary,
                  track: colors.secondaryContainer,
                  thickness: 4,
                  amplitude: 4,
                ),
              ),
            ),
          ),
          PercentText('$value', style: style?.copyWith(fontWeight: .w500)),
        ],
      ),
    );
  }
}

class _NotificationActionButton extends StatelessWidget {
  const _NotificationActionButton({
    required this.label,
    required this.prominent,
    required this.critical,
    required this.onPressed,
  });

  final String label;
  final bool prominent;
  final bool critical;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextButton.styleFrom(
      foregroundColor: prominent
          ? colors.onErrorContainer
          : critical
          ? colors.error
          : colors.primary,
      backgroundColor: prominent ? colors.errorContainer : null,
      minimumSize: const Size(0, 32),
      padding: const .symmetric(horizontal: 12),
      tapTargetSize: .padded,
      visualDensity: .standard,
    );
    return TextButton(
      onPressed: onPressed,
      style: style,
      child: Text(label, maxLines: 1, overflow: .ellipsis),
    );
  }
}

class _NotificationBody extends StatefulWidget {
  const _NotificationBody({
    required this.runs,
    required this.style,
    required this.link,
    required this.maxLines,
    required this.onLink,
  });

  final Iterable<Map> runs;
  final TextStyle? style;
  final Color link;
  final int? maxLines;
  final ValueChanged<String> onLink;

  @override
  State<_NotificationBody> createState() => _NotificationBodyState();
}

class _NotificationBodyState extends State<_NotificationBody> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _recognizer(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLink(href);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final text = Text.rich(
      TextSpan(children: [for (final run in widget.runs) _span(run)]),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? .visible : .ellipsis,
      style: widget.style,
    );
    return _recognizers.isEmpty ? ExcludeSemantics(child: text) : text;
  }

  TextSpan _span(Map run) {
    final text = '${run['text'] ?? ''}';
    final href = run['href'];
    final linked = href is String && href.isNotEmpty;
    return TextSpan(
      text: widget.maxLines == 1 ? text.replaceAll('\n', ' ') : text,
      mouseCursor: linked ? SystemMouseCursors.click : null,
      recognizer: linked ? _recognizer(href) : null,
      style: TextStyle(
        fontWeight: run['bold'] == true ? .w600 : null,
        fontStyle: run['italic'] == true ? .italic : null,
        color: linked ? widget.link : null,
        decoration: run['underline'] == true || linked ? .underline : null,
      ),
    );
  }
}

DateTime? _notificationDate(Object? received) =>
    received is int ? DateTime.fromMillisecondsSinceEpoch(received) : null;

String _relativeTime(BuildContext context, DateTime received) {
  final now = DateTime.now();
  final minutes = now.difference(received).inMinutes;
  if (minutes < 1) return 'now';
  if (minutes < 60) return '${minutes}m';
  if (DateUtils.isSameDay(now, received)) return '${minutes ~/ 60}h';
  if (DateUtils.isSameDay(
    DateTime(now.year, now.month, now.day - 1),
    received,
  )) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatShortDate(received);
}

/// A single accessible name for a history row or its toast announcement.
String notificationAccessibleName(BuildContext context, Map data) {
  final app = ((data['appName'] as String?) ?? '').trim();
  final title = (data['summary'] as String?) ?? '';
  final body = (data['body'] as List? ?? const [])
      .whereType<Map>()
      .map((run) => run['text'] ?? '')
      .join();
  final received = _notificationDate(data['received']);
  return [
    if (data['urgency'] == 2) 'Critical',
    app.isEmpty ? 'Notification' : app,
    if (title.isNotEmpty) title,
    if (body.isNotEmpty) body,
    if (received != null) _relativeTime(context, received),
  ].join(', ');
}

/// The received time with a full local date and time tooltip.
class NotificationTime extends StatelessWidget {
  const NotificationTime({super.key, required this.received, this.style});

  final Object? received;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final date = _notificationDate(received);
    if (date == null) return const SizedBox.shrink();
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Tooltip(
      message: '${localizations.formatFullDate(date)} · $time',
      child: Text(
        _relativeTime(context, date),
        style: style,
        maxLines: 1,
        overflow: .ellipsis,
      ),
    );
  }
}
