import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import '../system/system_backend.dart';
import 'resource_data.dart';
import 'resource_style.dart';

class BarResources extends StatelessWidget {
  const BarResources({
    super.key,
    this.snapshot,
    required this.cardSnapshot,
    this.compact = false,
    this.metrics,
  });

  final SystemSnapshot? snapshot;
  final SystemSnapshot? cardSnapshot;
  final bool compact;

  /// Shown metric names (`cpu`, `memory`, `gpu`, `network`); null shows all.
  final List<String>? metrics;

  static bool hasData(SystemSnapshot? snapshot, {List<String>? metrics}) =>
      _segments(snapshot, metrics).isNotEmpty;

  static double widthFor(
    BuildContext context, {
    bool compact = false,
    SystemSnapshot? snapshot,
    List<String>? metrics,
  }) {
    final segments = _segments(snapshot, metrics);
    if (segments.isEmpty) return 0;
    final gap = compact ? 6 : 14;
    return (compact ? 14 : 28) +
        gap * (segments.length - 1) +
        segments.fold(0.0, (width, segment) => width + segment.width(context));
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segments(snapshot, metrics);
    if (segments.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: .centerRight,
      child: BarPill(
        semanticsLabel: 'System resources',
        padding: compact
            ? const .fromLTRB(6, 0, 8, 0)
            : const .fromLTRB(6, 0, 12, 0),
        expandedPadding: compact
            ? const .fromLTRB(6, 0, 8, 0)
            : const .fromLTRB(12, 0, 16, 0),
        card: BarPillCard(
          kind: 'resources',
          size: const Size(420, 632),
          data: resourcePopupData(cardSnapshot),
          openOnTap: true,
        ),
        builder: (context, state) => Row(
          mainAxisSize: .min,
          spacing: compact
              ? 6
              : state.expanded
              ? 14
              : 12,
          children: [
            for (final segment in segments)
              _PillSegment(
                segment: segment,
                captions:
                    state.expanded &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.25,
                foreground: state.foreground,
              ),
          ],
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

List<_Segment> _segments(SystemSnapshot? snapshot, [List<String>? metrics]) => [
  for (final segment in _allSegments(snapshot))
    if (metrics?.contains(segment.metric.name) ?? true) segment,
];

List<_Segment> _allSegments(SystemSnapshot? snapshot) {
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
