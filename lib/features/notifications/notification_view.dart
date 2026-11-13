import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/percent_text.dart';
import '../../widgets/wave_progress.dart';
import '../popups/popup_measure.dart';
import '../tray/tray_icon.dart';

typedef NotificationAction = ValueChanged<Map<String, Object?>>;

/// The popup kind of the notification stack surface.
const notificationToastsKind = 'notification-toasts';

/// The notification center panel and center widget.
class NotificationCenterCard extends StatefulWidget {
  const NotificationCenterCard({
    super.key,
    required this.data,
    required this.onAction,
    this.onHeight,
  });

  final Map<String, Object?> data;
  final NotificationAction onAction;
  final ValueChanged<double>? onHeight;

  @override
  State<NotificationCenterCard> createState() => _NotificationCenterCardState();
}

class _NotificationCenterCardState extends State<NotificationCenterCard> {
  double? _topHeight;
  double? _bodyHeight;

  void _reportHeight(double pad) {
    final top = _topHeight;
    final body = _bodyHeight;
    final onHeight = widget.onHeight;
    if (top == null || body == null || onHeight == null) return;
    onHeight(top + body + pad * 2 + 16);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = [
      for (final item in widget.data['notifications'] as List? ?? const [])
        if (item is Map) item,
    ];
    final groups = <Object?, List<Map>>{};
    for (final item in items) {
      (groups[item['group']] ??= []).add(item);
    }
    final dnd = widget.data['dnd'];
    final error = widget.data['serviceError'];
    final panel = widget.onHeight != null;

    Widget content(double pad) {
      final headerAndDnd = Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  'Notifications',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 24,
                    height: 1.25,
                    fontWeight: .bold,
                    color: _emphasis(theme),
                  ),
                ),
              ),
              if (items.isNotEmpty)
                _Chip(
                  '${items.length}',
                  color: colors.primary,
                  foreground: colors.onPrimary,
                ),
              if (items.isNotEmpty)
                FilledButton.tonal(
                  onPressed: () =>
                      widget.onAction(const {'action': 'notification.clear'}),
                  child: const Text('Clear all'),
                ),
            ],
          ),
          if (dnd is bool)
            _DndTile(
              value: dnd,
              quietReason: widget.data['quietReason'],
              onChanged: (value) => widget.onAction({
                'action': 'notification.dnd',
                'value': value,
              }),
            ),
        ],
      );
      final body = Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          if (error is String)
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
          if (error == null && items.isEmpty)
            Padding(
              padding: const .symmetric(vertical: 16),
              child: Text(
                'No notifications',
                textAlign: .center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          for (final group in groups.values)
            Column(
              crossAxisAlignment: .stretch,
              spacing: 2,
              children: [
                for (final (index, item) in group.indexed)
                  NotificationTile(
                    data: item,
                    onAction: widget.onAction,
                    // Later group members drop the repeated app header.
                    showMeta: index == 0,
                    dismissIds: index == 0
                        ? [for (final item in group) item['id']]
                        : null,
                    radius: BorderRadius.vertical(
                      top: Radius.circular(index == 0 ? 20 : 6),
                      bottom: Radius.circular(
                        index == group.length - 1 ? 20 : 6,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
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
                child: headerAndDnd,
              ),
            ),
            Flexible(
              fit: .loose,
              child: SingleChildScrollView(
                primary: false,
                padding: .symmetric(horizontal: pad),
                child: PopupMeasure(
                  onHeight: (height) {
                    _bodyHeight = height;
                    _reportHeight(pad);
                  },
                  child: body,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!panel) return content(0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onAction(const {'action': 'close'}),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: colors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: .circular(32),
            side: BorderSide(color: colors.surfaceContainerHighest),
          ),
          clipBehavior: .antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                content(constraints.maxWidth < 340 ? 12.0 : 24.0),
          ),
        ),
      ),
    );
  }
}

class _DndTile extends StatelessWidget {
  const _DndTile({
    required this.value,
    required this.quietReason,
    required this.onChanged,
  });

  final bool value;
  final Object? quietReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: .circular(20),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const .fromLTRB(16, 12, 16, 12),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      'Do not disturb',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: .w500,
                        color: _emphasis(theme),
                      ),
                    ),
                    Text(
                      switch (quietReason) {
                        'schedule' => 'On by schedule',
                        'fullscreen' => 'On while an app is full screen',
                        _ => 'Critical notifications still show',
                      },
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Do not disturb',
                toggled: value,
                excludeSemantics: true,
                child: Switch(
                  padding: .zero,
                  materialTapTargetSize: .shrinkWrap,
                  value: value,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The popup stack, newest first, at the top left of the output focused when
/// the stack starts.
class NotificationToasts extends StatelessWidget {
  const NotificationToasts({
    super.key,
    required this.data,
    required this.onAction,
  });

  static const width = 372.0;

  /// Room for the shadow around the tiles.
  static const insets = EdgeInsets.fromLTRB(16, 0, 16, 24);

  final Map<String, Object?> data;
  final NotificationAction onAction;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) =>
        onAction(const {'action': 'notifications.hover', 'value': true}),
    onExit: (_) =>
        onAction(const {'action': 'notifications.hover', 'value': false}),
    child: Padding(
      padding: insets,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          for (final item in data['notifications'] as List? ?? const [])
            if (item is Map)
              TweenAnimationBuilder<double>(
                key: ValueKey(item['id']),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                curve: Easing.emphasizedDecelerate,
                tween: Tween(begin: 0, end: 1),
                builder: (context, progress, child) => Opacity(
                  opacity: progress,
                  child: FractionalTranslation(
                    translation: Offset(progress - 1, 0),
                    child: child,
                  ),
                ),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: .all(.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x4D000000),
                        offset: Offset(0, 6),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: NotificationTile(data: item, onAction: onAction),
                ),
              ),
        ],
      ),
    ),
  );
}

/// One notification in the Urgency=Low, Normal or Critical design variant.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.data,
    required this.onAction,
    this.showMeta = true,
    this.dismissIds,
    this.radius,
  });

  final Map data;
  final NotificationAction onAction;
  final bool showMeta;

  /// Notifications closed by this tile's close button; defaults to itself.
  final List<Object?>? dismissIds;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final urgency = data['urgency'];
    final critical = urgency == 2;
    final low = urgency == 0;
    final id = data['id'];
    final background = critical
        ? colors.errorContainer
        : low
        ? colors.surfaceContainerHigh
        : colors.surfaceContainerHighest;
    final foreground = critical
        ? colors.onErrorContainer
        : colors.onSurfaceVariant;
    final summaryColor = critical
        ? colors.onErrorContainer
        : low
        ? colors.onSurface
        : _emphasis(theme);
    final meta = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.2,
      color: foreground,
    );
    final summary = '${data['summary'] ?? ''}';
    final body = data['body'] as List? ?? const [];
    final actions = [
      for (final action in data['actions'] as List? ?? const [])
        if (action case [final String key, final String label]) (key, label),
    ];
    final progress = data['progress'];
    final image = _NotificationImage(data: data);
    final hasImage = data['imageArgb'] != null || data['image'] != null;
    final card = Padding(
      padding: critical
          ? const .fromLTRB(20, 20, 16, 20)
          : .fromLTRB(16, low ? 12 : 16, 12, low ? 12 : 16),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          if (showMeta)
            Row(
              spacing: 8,
              children: [
                _AppBadge(
                  data: data,
                  color: critical
                      ? colors.error
                      : low
                      ? colors.surfaceContainerHighest
                      : colors.secondaryContainer,
                  foreground: critical
                      ? colors.onError
                      : colors.onSecondaryContainer,
                ),
                Expanded(
                  child: Row(
                    spacing: 8,
                    children: [
                      Flexible(
                        child: Text(
                          '${data['appName'] ?? ''}'.isEmpty
                              ? 'Notification'
                              : '${data['appName']}',
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: meta?.copyWith(fontWeight: .w500),
                        ),
                      ),
                      Text('·', style: meta),
                      Text(_age(data['received']), style: meta),
                      if (critical)
                        _Chip(
                          'Critical',
                          color: colors.error,
                          foreground: colors.onError,
                          fontSize: 11,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  iconSize: 18,
                  visualDensity: .compact,
                  constraints: const .tightFor(width: 32, height: 32),
                  padding: .zero,
                  color: foreground,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    for (final target in dismissIds ?? [id]) {
                      onAction({
                        'action': 'notification.dismiss',
                        'id': target,
                      });
                    }
                  },
                ),
              ],
            ),
          Padding(
            padding: const .only(right: 4),
            child: Row(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [
                if (hasImage) image,
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: low ? 14 : 16,
                            height: 1.2,
                            fontWeight: .w500,
                            color: summaryColor,
                          ),
                        ),
                      if (body.isNotEmpty)
                        _NotificationBody(
                          runs: body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: low ? 13 : 14,
                            height: low ? 18 / 13 : 20 / 14,
                            color: foreground,
                          ),
                          link: colors.primary,
                          onLink: (href) => onAction({
                            'action': 'notification.link',
                            'href': href,
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (progress is int)
            Padding(
              padding: const .only(right: 4),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Progress $progress%',
                      child: SizedBox(
                        height: 12,
                        child: CustomPaint(
                          painter: WaveProgressPainter(
                            fraction: progress / 100,
                            active: critical ? colors.error : colors.primary,
                            track: critical
                                ? colors.onErrorContainer.withValues(alpha: .2)
                                : colors.secondaryContainer,
                            thickness: 4,
                            amplitude: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  PercentText(
                    '$progress',
                    style: meta?.copyWith(fontWeight: .w500),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const .only(right: 4),
              child: Wrap(
                alignment: .end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, (key, label)) in actions.indexed)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const .symmetric(horizontal: 12),
                        visualDensity: .compact,
                        tapTargetSize: .shrinkWrap,
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                        ),
                        backgroundColor: critical
                            ? index == 0
                                  ? colors.error
                                  : colors.error.withValues(alpha: .24)
                            : colors.secondaryContainer,
                        foregroundColor: critical
                            ? index == 0
                                  ? colors.onError
                                  : colors.onErrorContainer
                            : colors.onSecondaryContainer,
                      ),
                      onPressed: () => onAction({
                        'action': 'notification.invoke',
                        'id': id,
                        'key': key,
                      }),
                      child: Text(label, maxLines: 1, overflow: .ellipsis),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return Material(
      color: background,
      borderRadius: radius ?? .circular(critical ? 28 : 20),
      clipBehavior: .antiAlias,
      child: data['default'] == true
          ? InkWell(
              onTap: () => onAction({
                'action': 'notification.invoke',
                'id': id,
                'key': 'default',
              }),
              child: card,
            )
          : card,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
    this.label, {
    required this.color,
    required this.foreground,
    this.fontSize = 12,
  });

  final String label;
  final Color color;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Padding(
      padding: const .symmetric(horizontal: 8, vertical: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: fontSize,
          height: 1.2,
          fontWeight: .w500,
          color: foreground,
        ),
      ),
    ),
  );
}

class _AppBadge extends StatelessWidget {
  const _AppBadge({
    required this.data,
    required this.color,
    required this.foreground,
  });

  final Map data;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.chat_bubble_outline_rounded,
      size: 16,
      color: foreground,
    );
    final icon = data['icon'];
    final path = data['iconPath'];
    return Container(
      width: 24,
      height: 24,
      alignment: .center,
      decoration: ShapeDecoration(color: color, shape: const CircleBorder()),
      child: SizedBox.square(
        dimension: 16,
        child: icon is Uint8List
            ? Image.memory(icon, errorBuilder: (_, _, _) => fallback)
            : path is String
            ? Image.file(File(path), errorBuilder: (_, _, _) => fallback)
            : fallback,
      ),
    );
  }
}

class _NotificationImage extends StatelessWidget {
  const _NotificationImage({required this.data});

  final Map data;

  @override
  Widget build(BuildContext context) {
    final image = data['image'];
    return ClipRRect(
      borderRadius: .circular(16),
      child: SizedBox.square(
        dimension: 48,
        child: data['imageArgb'] is Uint8List
            ? TrayIcon(
                data: {
                  'argb': data['imageArgb'],
                  'width': data['imageWidth'],
                  'height': data['imageHeight'],
                },
                size: 48,
              )
            : image is Uint8List
            ? Image.memory(image, fit: .cover, gaplessPlayback: true)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Body runs with bold, italic, underline and links, clipped to three lines.
class _NotificationBody extends StatefulWidget {
  const _NotificationBody({
    required this.runs,
    required this.style,
    required this.link,
    required this.onLink,
  });

  final List runs;
  final TextStyle? style;
  final Color link;
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
    return Text.rich(
      TextSpan(
        children: [
          for (final run in widget.runs)
            if (run is Map)
              TextSpan(
                text: '${run['text'] ?? ''}',
                mouseCursor: '${run['href'] ?? ''}'.isEmpty
                    ? null
                    : SystemMouseCursors.click,
                recognizer: '${run['href'] ?? ''}'.isEmpty
                    ? null
                    : _recognizer(run['href'] as String),
                style: TextStyle(
                  fontWeight: run['bold'] == true ? .w600 : null,
                  fontStyle: run['italic'] == true ? .italic : null,
                  color: '${run['href'] ?? ''}'.isEmpty ? null : widget.link,
                  decoration:
                      run['underline'] == true ||
                          '${run['href'] ?? ''}'.isNotEmpty
                      ? .underline
                      : null,
                ),
              ),
        ],
      ),
      maxLines: 3,
      overflow: .ellipsis,
      style: widget.style,
    );
  }
}

Color _emphasis(ThemeData theme) => theme.brightness == .dark
    ? theme.colorScheme.primaryFixed
    : theme.colorScheme.onSurface;

/// Short receive age: now, 5m, 2h, 3d.
String _age(Object? received) {
  if (received is! int) return '';
  final seconds = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(received))
      .inSeconds;
  return switch (seconds) {
    < 60 => 'now',
    < 3600 => '${seconds ~/ 60}m',
    < 86400 => '${seconds ~/ 3600}h',
    _ => '${seconds ~/ 86400}d',
  };
}
