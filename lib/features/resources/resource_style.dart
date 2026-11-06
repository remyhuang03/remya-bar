import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

enum ResourceMetric {
  cpu('CPU', 0xff2196f3),
  memory('RAM', 0xff5cb82e),
  gpu('GPU', 0xfff2a900),
  network('NET', 0xff00a99d);

  const ResourceMetric(this.caption, this._seed);

  final String caption;
  final int _seed;

  static final _palettes = {
    for (final metric in values)
      metric: TonalPalette.fromHct(Hct.fromInt(metric._seed)),
  };

  ResourceColors colors(ColorScheme theme, {bool critical = false}) {
    if (critical) {
      return (
        color: theme.error,
        onColor: theme.onErrorContainer,
        container: theme.errorContainer,
        reading: theme.error,
        badge: theme.errorContainer,
      );
    }
    final dark = theme.brightness == .dark;
    final palette = _palettes[this]!;
    Color tone(int value) => Color(palette.get(value));
    final color = tone(dark ? 80 : 40);
    return (
      color: color,
      onColor: tone(dark ? 20 : 100),
      container: tone(dark ? 30 : 90),
      reading: tone(dark ? 90 : 10),
      badge: color,
    );
  }
}

typedef ResourceColors = ({
  Color color,
  Color onColor,
  Color container,
  Color reading,
  Color badge,
});

class ResourceGlyph extends StatelessWidget {
  const ResourceGlyph(
    this.name, {
    super.key,
    required this.color,
    this.outlineColor,
  });

  final String name;
  final Color color;
  final Color? outlineColor;

  @override
  Widget build(BuildContext context) {
    final size = switch (name) {
      'used' || 'cached' || 'free' => 8.0,
      'down' || 'up' => 12.0,
      'card-down' || 'card-up' => 16.0,
      'monitor' => 18.0,
      _ => 14.0,
    };
    final outline = outlineColor;
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        'assets/icons/resources/$name.svg',
        colorFilter: outline == null ? ColorFilter.mode(color, .srcIn) : null,
        colorMapper: outline == null ? null : _LegendColors(color, outline),
        excludeFromSemantics: true,
      ),
    );
  }
}

class _LegendColors extends ColorMapper {
  const _LegendColors(this.fill, this.stroke);
  final Color fill;
  final Color stroke;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => attributeName == 'stroke' ? stroke : fill;

  @override
  bool operator ==(Object other) =>
      other is _LegendColors && other.fill == fill && other.stroke == stroke;

  @override
  int get hashCode => Object.hash(fill, stroke);
}

class ResourceBadge extends StatelessWidget {
  const ResourceBadge({
    super.key,
    required this.metric,
    required this.colors,
    this.size = 20,
  });

  final ResourceMetric metric;
  final ResourceColors colors;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: .center,
    decoration: BoxDecoration(color: colors.badge, shape: .circle),
    child: ResourceGlyph(metric.name, color: colors.onColor),
  );
}

double? resourceNumber(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

double? resourcePercent(Object? value) {
  final number = resourceNumber(value);
  return number != null && number <= 100 ? number : null;
}

double? resourceUsage(double? used, double? total) =>
    used != null && total != null && total > 0
    ? resourcePercent(used / total * 100)
    : null;

bool resourceCritical(double? percent) => percent != null && percent > 90;

String resourcePercentLabel(double? value) =>
    value == null ? '—' : '${value.round()}%';

const _shortUnits = ['B', 'K', 'M', 'G', 'T', 'P', 'E'];
const _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];

({String number, String unit}) resourceAmount(
  double? bytes, {
  bool compact = false,
  bool rate = false,
  int? unitIndex,
}) {
  if (bytes == null) return (number: '—', unit: '');
  var unit = unitIndex ?? resourceUnit(bytes);
  var amount = bytes / math.pow(1000, unit);
  if (rate && amount > 0 && amount < 1) {
    return (number: '<1', unit: compact ? 'B' : 'B/s');
  }
  if (rate && amount > 0) {
    amount = double.parse(amount.toStringAsPrecision(2));
    if (amount >= 1000 && unit < _byteUnits.length - 1) {
      unit++;
      amount /= 1000;
    }
  }
  final decimals = rate
      ? (amount > 0 && amount < 10 ? 1 : 0)
      : (unit > 0 && amount != amount.truncateToDouble() ? 1 : 0);
  final suffix = compact ? _shortUnits[unit] : _byteUnits[unit];
  return (
    number: amount.toStringAsFixed(decimals),
    unit: rate && !compact ? '$suffix/s' : suffix,
  );
}

int resourceUnit(double bytes) {
  var index = 0;
  while (bytes >= 1000 && index < _byteUnits.length - 1) {
    bytes /= 1000;
    index++;
  }
  return index;
}

String resourceBytes(double? bytes, {bool compact = false}) {
  final amount = resourceAmount(bytes, compact: compact);
  return [
    amount.number,
    amount.unit,
  ].where((part) => part.isNotEmpty).join(compact ? '' : ' ');
}

String resourceRate(double? bytes, {bool compact = false}) {
  final amount = resourceAmount(bytes, compact: compact, rate: true);
  return [
    amount.number,
    amount.unit,
  ].where((part) => part.isNotEmpty).join(compact ? '' : ' ');
}
