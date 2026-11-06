import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../popups/bar_card_surface.dart';
import '../popups/bar_popup.dart';
import '../system/system_backend.dart';
import 'resource_data.dart';
import 'resource_style.dart';

class BarResources extends StatefulWidget {
  const BarResources({
    super.key,
    this.snapshot,
    required this.cardSnapshot,
    this.compact = false,
  });

  final SystemSnapshot? snapshot;
  final SystemSnapshot? cardSnapshot;
  final bool compact;

  static bool hasData(SystemSnapshot? snapshot) =>
      _segments(snapshot).isNotEmpty;

  static double widthFor(
    BuildContext context, {
    bool compact = false,
    SystemSnapshot? snapshot,
  }) {
    final segments = _segments(snapshot);
    if (segments.isEmpty) return 0;
    final gap = compact ? 6 : 14;
    return (compact ? 14 : 28) +
        gap * (segments.length - 1) +
        segments.fold(0.0, (width, segment) => width + segment.width(context));
  }

  @override
  State<BarResources> createState() => _BarResourcesState();
}

class _BarResourcesState extends State<BarResources> {
  final _pill = GlobalKey();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  bool _requested = false;

  void _send(Future<void> request) => unawaited(
    request.catchError((Object error) => debugPrint('System card: $error')),
  );

  void _show({bool update = false}) {
    final box = _pill.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _requested = true;
    final request = update ? BarPopup.update : BarPopup.show;
    _send(
      request(
        kind: 'resources',
        anchor: box.localToGlobal(.zero) & box.size,
        size: Size(
          420 + BarCardSurface.shadowInsets.horizontal,
          632 + BarCardSurface.shadowInsets.vertical,
        ),
        data: {
          ...resourcePopupData(widget.cardSnapshot),
          'scale': MediaQuery.textScalerOf(context).scale(1),
        },
        theme: BarPopupScope.themeOf(context),
      ),
    );
  }

  @override
  void dispose() {
    if (_requested) _send(BarPopup.hide(kind: 'resources'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segments(widget.snapshot);
    if (segments.isEmpty) return const SizedBox.shrink();
    if (_requested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(update: true);
      });
    }
    final colors = Theme.of(context).colorScheme;
    final expanded = _hovered || _focused || _pressed;
    final captions =
        expanded && MediaQuery.textScalerOf(context).scale(1) <= 1.25;
    final surface = _pressed
        ? colors.primaryContainer
        : expanded
        ? Color.alphaBlend(
            colors.onSurface.withValues(alpha: .08),
            colors.surfaceContainerHighest,
          )
        : colors.surfaceContainerHighest;
    final foreground = _pressed ? colors.onPrimaryContainer : colors.onSurface;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return Align(
      alignment: .centerRight,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          _show();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          _send(BarPopup.leave(kind: 'resources'));
        },
        child: Material(
          type: .transparency,
          child: Semantics(
            button: true,
            label: 'System resources',
            child: InkWell(
              onTap: _show,
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              child: AnimatedContainer(
                key: _pill,
                duration: duration,
                height: expanded ? 40 : 32,
                padding: widget.compact
                    ? const .fromLTRB(6, 0, 8, 0)
                    : expanded
                    ? const .fromLTRB(12, 0, 16, 0)
                    : const .fromLTRB(6, 0, 12, 0),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: .circular(_pressed ? 12 : 24),
                ),
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        border: .all(color: colors.primary, width: 2),
                        borderRadius: .circular(_pressed ? 12 : 24),
                      )
                    : null,
                child: Row(
                  mainAxisSize: .min,
                  spacing: widget.compact
                      ? 6
                      : expanded
                      ? 14
                      : 12,
                  children: [
                    for (final segment in segments)
                      _PillSegment(
                        segment: segment,
                        captions: captions,
                        foreground: foreground,
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

class _Segment {
  const _Segment(this.metric, this.value, {this.upload});

  final ResourceMetric metric;
  final double? value;
  final double? upload;

  bool get network => metric == .network;

  String get label => network
      ? resourceRate(value, compact: true)
      : resourcePercentLabel(value);

  double valueWidth(BuildContext context) =>
      _measure(context, network ? '444M' : '100%');

  double width(BuildContext context) =>
      26 + (network ? 32 + 2 * valueWidth(context) : valueWidth(context));
}

List<_Segment> _segments(SystemSnapshot? snapshot) {
  final memory = resourceUsage(
    snapshot?.memoryUsedBytes,
    snapshot?.memoryTotalBytes,
  );
  final network = snapshot?.networkOverview;
  return [
    if (resourcePercent(snapshot?.cpuPercent) case final cpu?)
      _Segment(.cpu, cpu),
    if (memory != null) _Segment(.memory, memory),
    if (resourcePercent(resourceGpu(snapshot)?.utilizationPercent)
        case final gpu?)
      _Segment(.gpu, gpu),
    if (resourceNumber(network?.downloadBytesPerSecond) case final download?)
      _Segment(
        .network,
        download,
        upload: resourceNumber(network?.uploadBytesPerSecond),
      )
    else if (resourceNumber(network?.uploadBytesPerSecond) case final upload?)
      _Segment(.network, null, upload: upload),
  ];
}

TextStyle _valueStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium!
    .copyWith(
      fontFamily: 'Inter',
      fontSize: 14,
      height: 18 / 14,
      fontWeight: .w500,
      letterSpacing: 0,
    );

double _measure(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _valueStyle(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

class _PillSegment extends StatelessWidget {
  const _PillSegment({
    required this.segment,
    required this.captions,
    required this.foreground,
  });

  final _Segment segment;
  final bool captions;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final critical = !segment.network && resourceCritical(segment.value);
    final colors = segment.metric.colors(scheme, critical: critical);
    final width = segment.valueWidth(context);
    final style = _valueStyle(context)
        .copyWith(color: critical ? scheme.error : foreground);
    Widget value(String text) => SizedBox(
      width: width,
      child: Text(text, maxLines: 1, overflow: .ellipsis, style: style),
    );
    final caption = segment.metric.caption;
    final semantics = switch (segment.metric) {
      .network =>
        'Download ${resourceRate(segment.value)}, upload ${resourceRate(segment.upload)}',
      .memory => 'Memory ${segment.label}',
      _ => '$caption ${segment.label}',
    };
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Row(
        spacing: 6,
        children: [
          ResourceBadge(metric: segment.metric, colors: colors),
          FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
            child: Column(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                if (captions)
                  Text(
                    caption,
                    style: theme.textTheme.labelSmall!.copyWith(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: .4,
                      fontWeight: .w600,
                      color: _pressedCaptionColor(scheme),
                    ),
                  ),
                if (segment.network)
                  Row(
                    spacing: 6,
                    children: [
                      for (final (icon, color, label) in [
                        ('down', scheme.primary, segment.label),
                        (
                          'up',
                          scheme.tertiary,
                          resourceRate(segment.upload, compact: true),
                        ),
                      ])
                        Row(
                          spacing: 1,
                          children: [
                            ResourceGlyph(icon, color: color),
                            value(label),
                          ],
                        ),
                    ],
                  )
                else
                  value(segment.label),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _pressedCaptionColor(ColorScheme scheme) =>
      foreground == scheme.onPrimaryContainer
      ? foreground
      : scheme.onSurfaceVariant;
}
