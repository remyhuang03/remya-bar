import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../bar_theme.dart';
import '../../widgets/bar_hover_card.dart';
import '../system/system_backend.dart';

const _batteryGreen = Color(0xFF0AC20A);
const _batteryYellow = Color(0xFFF2E70D);
const _batteryRed = Color(0xFFC2230A);

Color _batteryFillColor({required bool isLow, required bool isPowerSaver}) {
  if (isLow) return _batteryRed;
  if (isPowerSaver) return _batteryYellow;
  return _batteryGreen;
}

Color _batteryOnPrimary(Color seed) {
  final brightness =
      ThemeData.estimateBrightnessForColor(seed) == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).onPrimary;
}

class BarBattery extends StatelessWidget {
  const BarBattery({
    super.key,
    this.battery,
    this.level,
    this.isLow,
    this.isPowerSaver,
    this.isCharging,
    this.power = const {},
  });

  final BatterySnapshot? battery;
  final int? level;
  final bool? isLow;
  final bool? isPowerSaver;
  final bool? isCharging;
  final Map<String, Object?> power;

  @override
  Widget build(BuildContext context) {
    final charge = level ?? battery?.percent?.round();
    if (charge == null) return const SizedBox.shrink();

    final charging = isCharging ?? (battery?.state == 'Charging');
    final percent = charge.clamp(0, 100);
    final low = isLow ?? (percent <= 20);
    final powerSaver = isPowerSaver ?? false;

    final colors = Theme.of(context).colorScheme;
    final trackColor = colors.surfaceContainerHighest;
    final onTrackColor = colors.onSurfaceVariant;
    final fillColor = _batteryFillColor(isLow: low, isPowerSaver: powerSaver);
    final onFillColor = _batteryOnPrimary(fillColor);
    final fraction = percent / 100.0;
    final baseStyle =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle();

    Widget buildLabel(Color color) => Center(
      child: FittedBox(
        fit: .scaleDown,
        child: Row(
          mainAxisSize: .min,
          mainAxisAlignment: .center,
          crossAxisAlignment: .center,
          children: [
            if (charging) Icon(Icons.bolt_rounded, size: 14, color: color),
            Text(
              '$percent',
              style: baseStyle.copyWith(
                fontFamily: barFontFamily,
                fontFamilyFallback: barFontFamilyFallback,
                fontSize: 15,
                height: 1,
                fontFeatures: const [],
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: .center,
      child: SizedBox(
        width: 48,
        height: 24,
        child: BarHoverCard(
          kind: 'battery',
          size: const Size(420, 506),
          data: {
            'present': battery != null,
            'percent': battery?.percent,
            'status': battery?.state,
            'secondsRemaining': battery?.remainingSeconds,
            'powerWatts': battery?.powerWatts,
            'healthPercent': battery?.healthPercent,
            'cycleCount': battery?.cycleCount,
            'power': power,
          },
          child: Semantics(
            label: 'Battery $percent%${charging ? ', charging' : ''}',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: .circular(12),
              child: Stack(
                fit: .expand,
                children: [
                  if (percent < 100)
                    ColoredBox(
                      color: trackColor,
                      child: buildLabel(onTrackColor),
                    ),
                  if (percent > 0)
                    ClipPath(
                      clipper: _BatteryFillClipper(fraction),
                      child: ColoredBox(
                        color: fillColor,
                        child: buildLabel(onFillColor),
                      ),
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

class _BatteryFillClipper extends CustomClipper<Path> {
  const _BatteryFillClipper(this.fraction);

  final double fraction;

  @override
  Path getClip(Size size) {
    if (fraction >= 1) return Path()..addRect(Offset.zero & size);

    final radius = 4 + 20 * fraction;
    // Extend vertically so RRect keeps the requested radius above 12 px.
    final height = math.max(size.height, 2 * radius);
    final right = size.width * fraction;
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(
          right - size.width,
          (size.height - height) / 2,
          size.width,
          height,
        ),
        topRight: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
    );
  }

  @override
  bool shouldReclip(covariant _BatteryFillClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
