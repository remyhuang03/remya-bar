import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../widgets/percent_text.dart';
import 'resource_style.dart';

class ResourceCard extends StatelessWidget {
  const ResourceCard({
    super.key,
    required this.data,
    required this.onOpenMonitor,
  });

  final Map<String, Object?> data;
  final VoidCallback onOpenMonitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    double? number(String key) => resourceNumber(data[key]);
    final cpuTemperature = _temperature(number('cpuTemperature'));
    final gpuTemperature = _temperature(number('gpuTemperature'));
    final cpu = _ComputeTile(
      metric: .cpu,
      value: resourcePercent(data['cpu']),
      history: _history(data['cpuHistory']),
      detail: [
        if (number('cores') case final cores?) '${cores.round()} cores',
        if (number('frequency') case final frequency?)
          '${frequency.toStringAsFixed(1)} GHz',
        ?cpuTemperature,
      ].join(' · '),
    );
    final gpu = data['gpuName'] is String
        ? _ComputeTile(
            metric: .gpu,
            value: resourcePercent(data['gpu']),
            history: _history(data['gpuHistory']),
            detail: [
              if (number('gpuTotal') case final total?)
                'VRAM ${_usageLabel(number('gpuUsed'), total)}',
              ?gpuTemperature,
            ].join(' · '),
          )
        : null;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'System',
                  style: theme.textTheme.titleLarge!.copyWith(
                    fontSize: 24,
                    fontWeight: .w700,
                    color: colors.brightness == .dark
                        ? colors.primaryFixed
                        : colors.onSurface,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Open system monitor',
                onPressed: onOpenMonitor,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(40),
                  padding: .zero,
                ),
                icon: ResourceGlyph(
                  'monitor',
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (gpu == null)
          cpu
        else
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >=
                    320 * MediaQuery.textScalerOf(context).scale(1)
                ? Row(
                    crossAxisAlignment: .start,
                    spacing: 12,
                    children: [
                      Expanded(child: cpu),
                      Expanded(child: gpu),
                    ],
                  )
                : Column(
                    crossAxisAlignment: .stretch,
                    spacing: 12,
                    children: [cpu, gpu],
                  ),
          ),
        _MemoryTile(data: data),
        _NetworkTile(data: data),
        const _Note('Updated every second · last 60 s'),
      ],
    );
  }
}

List<double?> _history(Object? data) =>
    data is List ? data.map(resourceNumber).toList(growable: false) : const [];

String? _temperature(double? value) =>
    value == null ? null : '${value.round()}°C';

String _usageLabel(double? used, double total) {
  final unit = resourceUnit(total);
  final usedAmount = resourceAmount(used, unitIndex: unit);
  final totalAmount = resourceAmount(total, unitIndex: unit);
  return '${usedAmount.number} / ${totalAmount.number} ${totalAmount.unit}';
}

class _Tile extends StatelessWidget {
  const _Tile({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: .circular(20),
    ),
    child: Padding(
      padding: const .all(16),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: children,
      ),
    ),
  );
}

class _TileHeader extends StatelessWidget {
  const _TileHeader(this.metric, this.colors, this.label, {this.trailing});

  final ResourceMetric metric;
  final ResourceColors colors;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      ResourceBadge(metric: metric, colors: colors, size: 24),
      Expanded(
        child: Text(
          label,
          style: _textStyle(context, 14).copyWith(fontWeight: .w500),
        ),
      ),
      if (trailing case final widget?)
        Flexible(
          flex: 2,
          child: Align(alignment: .centerRight, child: widget),
        ),
    ],
  );
}

TextStyle _textStyle(BuildContext context, double size) {
  final theme = Theme.of(context);
  return theme.textTheme.bodySmall!.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    fontSize: size,
    height: 1.25,
    letterSpacing: 0,
  );
}

class _Note extends StatelessWidget {
  const _Note(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: _textStyle(context, 12));
}

class _Reading extends StatelessWidget {
  const _Reading(
    this.number,
    this.unit,
    this.color, {
    this.size = 20,
    this.unitSize = 14,
  });

  final String number;
  final String unit;
  final Color color;
  final double size;
  final double unitSize;

  @override
  Widget build(BuildContext context) {
    if (unit == '%') {
      return PercentText(
        number,
        style: _textStyle(
          context,
          size,
        ).copyWith(fontWeight: .w700, color: color),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: number,
            style: _textStyle(
              context,
              size,
            ).copyWith(fontWeight: .w700, color: color),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: _textStyle(context, unitSize).copyWith(fontWeight: .w500),
            ),
        ],
      ),
    );
  }
}

class _ComputeTile extends StatelessWidget {
  const _ComputeTile({
    required this.metric,
    required this.value,
    required this.history,
    required this.detail,
  });

  final ResourceMetric metric;
  final double? value;
  final List<double?> history;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = metric.colors(scheme, critical: resourceCritical(value));
    return _Tile(
      children: [
        _TileHeader(metric, colors, metric.caption),
        _Reading(
          value?.round().toString() ?? '—',
          value == null ? '' : '%',
          colors.reading,
          size: 32,
          unitSize: 16,
        ),
        SizedBox(
          height: 36,
          child: CustomPaint(
            painter: _Trend(history, colors.color),
            child: const SizedBox.expand(),
          ),
        ),
        _Note(detail.isEmpty ? 'Details unavailable' : detail),
      ],
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.data});

  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = resourceNumber(data['memoryUsed']);
    final total = resourceNumber(data['memoryTotal']);
    final cached = resourceNumber(data['memoryCached']);
    final free = resourceNumber(data['memoryFree']);
    final swap = resourceNumber(data['swapTotal']);
    final colors = ResourceMetric.memory.colors(
      scheme,
      critical: resourceCritical(resourceUsage(used, total)),
    );
    final sections = [
      ('Used', 'used', used, colors.color),
      ('Cached', 'cached', cached, colors.container),
      ('Free', 'free', free, scheme.surfaceContainer),
    ];
    final unit = resourceUnit(total ?? 0);
    final usedAmount = resourceAmount(used, unitIndex: unit);
    final totalAmount = resourceAmount(total, unitIndex: unit);
    final filled = [
      if (total != null && total > 0) ...[
        for (final (_, _, bytes, color) in sections)
          if (bytes != null && bytes > 0) (bytes, color),
        if (total - (used ?? 0) - (cached ?? 0) - (free ?? 0) case final missing
            when missing > 0)
          (missing, scheme.surfaceContainer),
      ],
    ];
    return _Tile(
      children: [
        _TileHeader(
          .memory,
          colors,
          'Memory',
          trailing: _Reading(
            usedAmount.number,
            total == null ? '' : ' / ${totalAmount.number} ${totalAmount.unit}',
            colors.reading,
          ),
        ),
        SizedBox(
          height: 12,
          child: ClipRRect(
            borderRadius: .circular(6),
            child: Row(
              crossAxisAlignment: .stretch,
              spacing: 4,
              children: [
                if (filled.isEmpty)
                  Expanded(child: ColoredBox(color: scheme.surfaceContainer))
                else
                  for (final (bytes, color) in filled)
                    Expanded(
                      flex: math.max(
                        1,
                        (bytes / (total ?? bytes) * 1000).round(),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: .circular(2),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final (label, icon, bytes, color) in sections)
              Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  ResourceGlyph(
                    icon,
                    color: color,
                    outlineColor: icon == 'free' ? scheme.outlineVariant : null,
                  ),
                  _Note('$label ${resourceBytes(bytes, compact: true)}'),
                ],
              ),
          ],
        ),
        _Note(switch (swap) {
          null => 'Swap —',
          0 => 'Swap off',
          final total =>
            'Swap ${_usageLabel(resourceNumber(data['swapUsed']), total)}',
        }),
      ],
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.data});

  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ResourceMetric.network.colors(scheme);
    final label = data['networkLabel'];
    final todayDown = resourceBytes(resourceNumber(data['downloadToday']));
    final todayUp = resourceBytes(resourceNumber(data['uploadToday']));
    final partial = data['todayPartial'] == true;
    return _Tile(
      children: [
        _TileHeader(
          .network,
          colors,
          'Network',
          trailing: label is String && label.isNotEmpty ? _Note(label) : null,
        ),
        Row(
          spacing: 16,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  for (final (name, icon) in const [
                    ('download', 'card-down'),
                    ('upload', 'card-up'),
                  ])
                    _NetworkReading(
                      label: name,
                      icon: icon,
                      iconColor: colors.color,
                      readingColor: colors.reading,
                      value: resourceNumber(data[name]),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 60,
                child: CustomPaint(
                  painter: _Trend(
                    _history(data['downloadHistory']),
                    colors.color,
                    upload: _history(data['uploadHistory']),
                    axis: scheme.outlineVariant,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
        _Note(
          '${partial ? 'Today (observed)' : 'Today'}  ↓ $todayDown  ·  ↑ $todayUp',
        ),
      ],
    );
  }
}

class _NetworkReading extends StatelessWidget {
  const _NetworkReading({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.readingColor,
    required this.value,
  });

  final String label;
  final String icon;
  final Color iconColor;
  final Color readingColor;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final rate = resourceAmount(value, rate: true);
    return Semantics(
      label: '$label ${resourceRate(value)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: .min,
        spacing: 4,
        children: [
          ResourceGlyph(icon, color: iconColor),
          Flexible(
            child: _Reading(
              rate.number,
              ' ${rate.unit}',
              readingColor,
              unitSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Trend extends CustomPainter {
  const _Trend(this.values, this.color, {this.upload, this.axis});

  final List<double?> values;
  final Color color;
  final List<double?>? upload;
  final Color? axis;

  @override
  void paint(Canvas canvas, Size size) {
    final mirrored = upload != null;
    final baseline = mirrored ? size.height / 2 : size.height;
    if (axis case final line?) {
      canvas.drawLine(
        Offset(0, baseline),
        Offset(size.width, baseline),
        Paint()..color = line,
      );
    }
    void bars(List<double?> series, {bool below = false}) {
      if (series.isEmpty || size.width <= 0) return;
      final peak = mirrored
          ? series.whereType<double>().fold(0.0, math.max)
          : 100.0;
      final slot = size.width / series.length;
      final width = math.min(6.0, slot * .75);
      final extent = mirrored ? baseline - 2 : baseline;
      for (var i = 0; i < series.length; i++) {
        final value = series[i];
        if (value == null) continue;
        final ratio = peak > 0 ? (value / peak).clamp(0, 1) : 0;
        final height = math.max(2.0, extent * ratio);
        final top = below
            ? baseline + 2
            : baseline - (mirrored ? 2 : 0) - height;
        final left = i * slot + (slot - width) / 2;
        final alpha = .35 + .65 * i / math.max(1, series.length - 1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, width, height),
            const .circular(3),
          ),
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }

    bars(values);
    if (upload case final series?) bars(series, below: true);
  }

  @override
  bool shouldRepaint(_Trend oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.upload != upload ||
      oldDelegate.color != color ||
      oldDelegate.axis != axis;
}
