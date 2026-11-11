import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'ai_quota_ring.dart';
import 'ai_usage_data.dart';

class AiUsageCard extends StatelessWidget {
  const AiUsageCard({super.key, required this.data, required this.onRefresh});

  final Map<String, Object?> data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = Theme.of(context).colorScheme;
    final updated = aiDate(data['updatedAt']);
    final age = updated == null ? null : now.difference(updated);
    final refresh = data['refreshing'] == true ? null : onRefresh;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'AI Usage',
                style: _style(
                  context,
                  24,
                  color: _headline(colors),
                  weight: .w700,
                ),
              ),
            ),
            Padding(
              padding: const .only(right: 4),
              child: IconButton.filledTonal(
                tooltip: 'Refresh',
                onPressed: refresh,
                icon: SvgPicture.asset(
                  'assets/icons/ai_usage/refresh.svg',
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(
                    refresh == null
                        ? colors.onSurface.withValues(alpha: .38)
                        : colors.onSecondaryContainer,
                    .srcIn,
                  ),
                ),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(40),
                  padding: .zero,
                ),
              ),
            ),
          ],
        ),
        for (final provider in aiVisibleProviders(data, now))
          _ProviderTile(provider: provider, showUsed: data['showUsed'] == true),
        _SpendTile(rows: aiRows(data['cost']), now: now),
        if (age != null)
          Text(
            age.inMinutes <= 0
                ? 'Updated <1 min ago'
                : 'Updated ${age.inMinutes} min ago',
            style: _style(context, 12),
          ),
      ],
    );
  }
}

Color _headline(ColorScheme scheme) =>
    scheme.brightness == .dark ? scheme.primaryFixed : scheme.primary;

TextStyle _style(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight? weight,
}) => Theme.of(context).textTheme.bodySmall!.copyWith(
  fontSize: size,
  height: 1.25,
  fontWeight: weight,
  letterSpacing: 0,
  color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
);

class _Tile extends StatelessWidget {
  const _Tile({required this.children, this.spacing = 14});

  final List<Widget> children;
  final double spacing;

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
        spacing: spacing,
        children: children,
      ),
    ),
  );
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.showUsed});

  final AiQuotaProvider provider;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = provider.data;
    final nameStyle = _style(
      context,
      14,
      color: colors.onSurface,
      weight: .w500,
    );
    return _Tile(
      children: [
        Row(
          spacing: 8,
          children: [
            AiQuotaRing(provider, showUsed: showUsed),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: .center,
                children: [
                  Text(provider.name, style: nameStyle),
                  if (aiText(data['plan']) case final plan?)
                    _Chip(
                      plan,
                      colors.secondaryContainer,
                      colors.onSecondaryContainer,
                    ),
                  if (aiText(data['incident']) case final incident?)
                    _Chip(
                      incident,
                      colors.errorContainer,
                      colors.onErrorContainer,
                    ),
                ],
              ),
            ),
            if (aiText(data['source']) case final source? when source != 'auto')
              Text(switch (source) {
                'oauth' => 'OAuth',
                'cli' => 'CLI',
                'api' => 'API',
                'web' || 'openai-web' => 'Web',
                _ => source,
              }, style: _style(context, 12)),
          ],
        ),
        for (final slot in quotaSlots)
          if (provider.window(slot) case final window?)
            _WindowRow(window, showUsed: showUsed),
        if (aiNumber(data['credits']) case final credits? when credits > 0)
          _BalanceRow(
            'Credits',
            '${credits.toStringAsFixed(credits == credits.round() ? 0 : 1)} left',
          ),
        if (data['bankedResets'] case final int count when count > 0)
          _BalanceRow('Banked resets', '$count'),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: _style(context, 12))),
      Text(
        value,
        style: _style(
          context,
          12,
          color: Theme.of(context).colorScheme.onSurface,
          weight: .w500,
        ),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.background, this.foreground);

  final String label;
  final Color background, foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: background, borderRadius: .circular(99)),
    child: Padding(
      padding: const .symmetric(horizontal: 8, vertical: 2),
      child: Text(
        label,
        maxLines: 1,
        overflow: .ellipsis,
        style: _style(context, 11, color: foreground, weight: .w500),
      ),
    ),
  );
}

class _WindowRow extends StatelessWidget {
  const _WindowRow(this.window, {required this.showUsed});

  final AiQuotaWindow window;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = window.slot == 'tertiary';
    final percent = showUsed
        ? '${(100 - window.left).round()}%'
        : window.percent;
    final caption = switch (window.cadence) {
      '1W' => compact ? 'weekly' : 'all models',
      final cadence when cadence != window.name =>
        '${cadence.toLowerCase()} window',
      _ => null,
    };
    final reset = window.resetLabel;
    final pace = window.paceLabel;
    final small = _style(context, 12);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          crossAxisAlignment: .baseline,
          textBaseline: .alphabetic,
          spacing: 8,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: window.name,
                      style: _style(
                        context,
                        compact ? 12 : 14,
                        color: colors.onSurface,
                        weight: .w500,
                      ),
                    ),
                    if (caption != null) TextSpan(text: '  $caption'),
                  ],
                ),
                style: small,
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: percent,
                    style: _style(
                      context,
                      compact ? 12 : 20,
                      color: window.low
                          ? colors.error
                          : compact
                          ? colors.onSurfaceVariant
                          : _headline(colors),
                      weight: compact ? .w500 : .w700,
                    ),
                  ),
                  TextSpan(text: showUsed ? ' used' : ' left'),
                ],
              ),
              style: small,
            ),
          ],
        ),
        _QuotaMeter(window, compact: compact, showUsed: showUsed),
        if (!compact && (reset != null || pace != null))
          Row(
            spacing: 4,
            children: [
              if (reset != null)
                SvgPicture.asset(
                  'assets/icons/ai_usage/schedule.svg',
                  width: 14,
                  height: 14,
                  colorFilter: ColorFilter.mode(
                    colors.onSurfaceVariant,
                    .srcIn,
                  ),
                ),
              Expanded(child: Text(reset ?? '', style: small)),
              if (pace != null)
                Expanded(
                  child: Text(
                    pace,
                    textAlign: .end,
                    style: small.copyWith(
                      fontWeight: .w500,
                      color: window.runningOut ? colors.error : null,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _QuotaMeter extends StatelessWidget {
  const _QuotaMeter(
    this.window, {
    required this.compact,
    required this.showUsed,
  });

  final AiQuotaWindow window;
  final bool compact, showUsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fill = (showUsed ? 100 - window.left : window.left) / 100;
    final expected = window.expectedLeft;
    final pace = expected == null
        ? null
        : (showUsed ? 100 - expected : expected) / 100;
    final height = compact ? 4.0 : 8.0;
    final activeColor = window.low ? colors.error : colors.primary;
    final outer = Radius.circular(height / 2);
    final inner = Radius.circular(height / 4);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final active = width * fill;
            final gap = fill == 0 || fill == 1
                ? 0.0
                : 4.0.clamp(0.0, width - active);
            return Stack(
              clipBehavior: .none,
              children: [
                if (fill > 0)
                  Positioned(
                    left: 0,
                    width: active,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: .horizontal(
                          left: outer,
                          right: fill == 1 ? outer : inner,
                        ),
                      ),
                    ),
                  ),
                if (fill < 1)
                  Positioned(
                    left: active + gap,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: .horizontal(
                          left: fill == 0 ? outer : inner,
                          right: outer,
                        ),
                      ),
                    ),
                  ),
                if (!compact && width - active - gap >= 6)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: SvgPicture.asset(
                      'assets/icons/ai_usage/stop.svg',
                      width: 4,
                      height: 4,
                      colorFilter: ColorFilter.mode(activeColor, .srcIn),
                    ),
                  ),
                if (pace != null && width >= 2)
                  Positioned(
                    left: (width * pace - 1).clamp(0.0, width - 2),
                    top: compact ? -3 : -4,
                    bottom: compact ? -3 : -4,
                    width: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.onSurface,
                        borderRadius: .circular(1),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpendTile extends StatelessWidget {
  const _SpendTile({required this.rows, required this.now});

  final List<Map<String, Object?>> rows;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final small = _style(context, 12);
    // Calendar arithmetic must not skip a date when the local offset changes.
    final date = DateTime.utc(now.year, now.month, now.day);
    final dates = [
      for (var i = 29; i >= 0; i--)
        date.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
    ];
    final days = [
      for (final day in dates)
        [for (final row in rows) aiNumber(aiMap(row['daily'])[day]) ?? 0.0],
    ];
    final peak = days.map(_sum).fold(0.0, math.max);
    final total = rows.map((row) => aiNumber(row['total'])).nonNulls.toList();
    final tokens = rows.map((row) => aiNumber(row['tokens'])).nonNulls.toList();
    final hasToday = rows.any(
      (row) => aiMap(row['daily']).containsKey(dates.last),
    );
    final partial = rows.any((row) => row['partial'] == true);
    Color seriesColor(Map<String, Object?> row) =>
        row['id'] == 'codex' ? colors.tertiary : colors.primary;
    String dollars(double value) => '\$${value.toStringAsFixed(2)}';
    return _Tile(
      spacing: 10,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                'Spend',
                style: _style(context, 14, color: colors.onSurface),
              ),
            ),
            Expanded(
              child: Text(
                partial
                    ? 'Partial local estimate'
                    : 'Local estimate · API rates',
                textAlign: .end,
                style: small,
              ),
            ),
          ],
        ),
        if (rows.isEmpty)
          Text('Spend unavailable', style: small)
        else ...[
          Wrap(
            alignment: .spaceBetween,
            crossAxisAlignment: .end,
            spacing: 8,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: hasToday ? dollars(_sum(days.last)) : '—',
                      style: _style(
                        context,
                        32,
                        color: _headline(colors),
                        weight: .w700,
                      ),
                    ),
                    TextSpan(text: ' today', style: _style(context, 16)),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: total.isEmpty ? '—' : dollars(_sum(total)),
                      style: _style(
                        context,
                        16,
                        color: colors.onSurface,
                        weight: .w700,
                      ),
                    ),
                    const TextSpan(text: ' / 30 days'),
                  ],
                ),
                style: small,
              ),
            ],
          ),
          Semantics(
            label: 'Daily estimated spend, last 30 days',
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  for (final (day, values) in days.indexed)
                    Expanded(
                      child: Align(
                        alignment: .bottomCenter,
                        child: SizedBox(
                          width: 6,
                          child: Column(
                            mainAxisAlignment: .end,
                            children: [
                              if (_sum(values) == 0)
                                _bar(colors.outlineVariant, 2)
                              else
                                for (final (index, value)
                                    in values.indexed.toList().reversed)
                                  if (value > 0)
                                    _bar(
                                      seriesColor(
                                        rows[index],
                                      ).withValues(alpha: .45 + .55 * day / 29),
                                      value / peak * 40,
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            alignment: .spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final row in rows)
                if (aiNumber(row['total']) case final amount?)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '● ',
                          style: small.copyWith(color: seriesColor(row)),
                        ),
                        TextSpan(
                          text:
                              '${row['id'] == 'codex' ? 'Codex' : 'Claude'} ${dollars(amount)}',
                        ),
                      ],
                    ),
                    style: small,
                  ),
              if (tokens.isNotEmpty)
                Text('${_tokenLabel(_sum(tokens))} tokens', style: small),
            ],
          ),
        ],
      ],
    );
  }
}

Widget _bar(Color color, double height) => Container(
  height: height,
  decoration: BoxDecoration(color: color, borderRadius: .circular(3)),
);

double _sum(Iterable<double> values) =>
    values.fold(0, (sum, value) => sum + value);

String _tokenLabel(double value) => switch (value) {
  >= 1000000000 => '${(value / 1000000000).toStringAsFixed(1)}B',
  >= 1000000 => '${(value / 1000000).toStringAsFixed(1)}M',
  >= 1000 => '${(value / 1000).toStringAsFixed(1)}K',
  _ => value.round().toString(),
};
