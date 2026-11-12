import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

const osdKind = 'osd';
const osdSize = Size(260, 76);

enum OsdType {
  volume,
  brightness,
  gamma;

  static OsdType? fromName(Object? name) => switch (name) {
    'volume' => .volume,
    'brightness' => .brightness,
    'gamma' => .gamma,
    _ => null,
  };
}

/// Default output volume ceiling when no preference has been read.
const osdVolumeMax = 150;

typedef OsdAccent = ({Color color, Color onColor});

/// Custom M3 accents shared by the OSD and the sidebar sliders: Boost marks
/// volume above 100%, Gamma marks software dimming.
abstract final class OsdAccents {
  static OsdAccent boost(ColorScheme scheme) => _harmonized(0xFFB16415, scheme);

  static OsdAccent gamma(ColorScheme scheme) => _harmonized(0xFF4677C2, scheme);

  static OsdAccent _harmonized(int seed, ColorScheme scheme) {
    final harmonized = Blend.harmonize(seed, scheme.primary.toARGB32());
    final palette = TonalPalette.fromHct(Hct.fromInt(harmonized));
    final dark = scheme.brightness == .dark;
    return (
      color: Color(palette.get(dark ? 80 : 40)),
      onColor: Color(palette.get(dark ? 20 : 100)),
    );
  }
}

class OsdCapsuleSlider extends StatelessWidget {
  const OsdCapsuleSlider({
    super.key,
    required this.type,
    required this.value,
    this.muted = false,
    this.preMuteValue,
    this.max = osdVolumeMax,
  });

  factory OsdCapsuleSlider.fromData(Map<String, Object?> data) {
    final type = OsdType.fromName(data['type']) ?? .volume;
    final rawValue = data['value'];
    final value = rawValue is num ? rawValue.round() : 0;
    final rawPreMute = data['preMuteValue'];
    final rawMax = data['max'];
    return OsdCapsuleSlider(
      type: type,
      value: value,
      muted: type == .volume && data['muted'] == true,
      preMuteValue: rawPreMute is num ? rawPreMute.round() : null,
      max: rawMax is num && rawMax >= 100 ? rawMax.round() : osdVolumeMax,
    );
  }

  final OsdType type;
  final int value;
  final bool muted;
  final int? preMuteValue;

  /// Volume track end; values above 100 are Boost. Ignored for brightness.
  final int max;

  static const _capsuleHeight = 48.0;
  static const _tagHeight = 28.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _capsule(context, math.min(osdSize.width, constraints.maxWidth)),
  );

  Widget _capsule(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final isVolume = type == .volume;
    // Zero volume and mute are the same state.
    final isMuted = isVolume && (muted || value <= 0);
    final maxValue = isVolume ? max : 100;
    final percent = value.clamp(0, maxValue);
    final level = isMuted
        ? (preMuteValue ?? percent).clamp(0, maxValue)
        : percent;
    final isBoost = isVolume && !isMuted && level > 100;
    final isMax = !isMuted && level == maxValue;
    final dimming = type == .gamma && percent < 100;
    final boost = OsdAccents.boost(scheme);
    final gamma = OsdAccents.gamma(scheme);

    const left = 4.0;
    final right = 196 * width / osdSize.width;
    double position(int value) =>
        (44 + 150 * value / maxValue) * width / osdSize.width;
    final thumb = position(level);
    final threshold = position(100);
    final filledEnd = isBoost
        ? threshold - 2
        : isMax
        ? right
        : thumb - 6;
    final filledColor = isMuted
        ? scheme.onSurface.withValues(alpha: 0.12)
        : dimming
        ? gamma.color
        : scheme.primary;
    final thumbColor = isMuted
        ? scheme.outline
        : isBoost
        ? boost.color
        : filledColor;
    final icon = switch (type) {
      .volume => isMuted ? 'volume-off' : 'volume-up',
      .brightness => 'brightness',
      .gamma => 'gamma',
    };
    final iconColor = isMuted
        ? scheme.onSurface
        : dimming
        ? gamma.onColor
        : scheme.onPrimary;
    final tag = switch (type) {
      .volume when isBoost => (
        text: 'Boost',
        color: boost.color,
        foreground: boost.onColor,
      ),
      .gamma when dimming => (
        text: 'Software brightness',
        color: gamma.color,
        foreground: gamma.onColor,
      ),
      .gamma => (
        text: 'Dimming off',
        color: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
      _ => null,
    };

    return SizedBox(
      width: width,
      height: osdSize.height,
      child: Stack(
        children: [
          if (tag != null)
            _OsdTag(
              text: tag.text,
              color: tag.color,
              foreground: tag.foreground,
              width: width,
              center: thumb,
            ),
          Positioned(
            top: _tagHeight,
            left: 0,
            right: 0,
            height: _capsuleHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: .circular(24),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Stack(
                children: [
                  _OsdTrack(
                    start: left,
                    end: filledEnd,
                    color: filledColor,
                    roundStart: true,
                    roundEnd: isMax && !isBoost,
                  ),
                  if (isBoost)
                    _OsdTrack(
                      start: threshold + 2,
                      end: isMax ? right : thumb - 6,
                      color: boost.color,
                      roundEnd: isMax,
                    ),
                  if (!isMax) ...[
                    _OsdTrack(
                      start: thumb + 6,
                      end: right,
                      color: isMuted
                          ? scheme.surfaceContainerHighest
                          : scheme.secondaryContainer,
                      roundEnd: true,
                    ),
                    Positioned(
                      key: const ValueKey('osd-handle'),
                      left: thumb - 2,
                      top: 10,
                      width: 4,
                      height: 28,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: thumbColor,
                          borderRadius: .circular(2),
                        ),
                      ),
                    ),
                  ],
                  if (isVolume &&
                      maxValue > 100 &&
                      (level < 100 || isMuted) &&
                      (thumb - threshold).abs() >= 4)
                    Positioned(
                      key: const ValueKey('osd-100-marker'),
                      left: threshold - 2,
                      top: 22,
                      width: 4,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: isMuted ? scheme.outline : scheme.primary,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    top: 14,
                    width: 20,
                    height: 20,
                    child: SvgPicture.asset(
                      'assets/icons/osd/$icon.svg',
                      colorFilter: ColorFilter.mode(iconColor, .srcIn),
                    ),
                  ),
                  Positioned(
                    left: right + 4,
                    right: 16,
                    top: 10,
                    bottom: 10,
                    child: FittedBox(
                      alignment: .centerRight,
                      fit: .scaleDown,
                      child: Text(
                        isMuted ? 'Muted' : '$percent%',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: .w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OsdTrack extends StatelessWidget {
  const _OsdTrack({
    required this.start,
    required this.end,
    required this.color,
    this.roundStart = false,
    this.roundEnd = false,
  });

  final double start;
  final double end;
  final Color color;
  final bool roundStart;
  final bool roundEnd;

  @override
  Widget build(BuildContext context) {
    if (end <= start) return const SizedBox.shrink();
    final left = Radius.circular(roundStart ? 20 : 4);
    final right = Radius.circular(roundEnd ? 20 : 4);
    return Positioned(
      left: start,
      top: 4,
      width: end - start,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.horizontal(left: left, right: right),
        ),
      ),
    );
  }
}

class _OsdTag extends StatelessWidget {
  const _OsdTag({
    required this.text,
    required this.color,
    required this.foreground,
    required this.width,
    required this.center,
  });

  final String text;
  final Color color;
  final Color foreground;
  final double width;
  final double center;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: .w500,
      color: foreground,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final tagWidth = math.min(width, painter.width.ceilToDouble() + 16);
    painter.dispose();
    return Positioned(
      left: (center - tagWidth / 2).clamp(0.0, width - tagWidth),
      top: 0,
      width: tagWidth,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: .circular(10)),
        child: Padding(
          padding: const .symmetric(horizontal: 8, vertical: 3),
          child: FittedBox(
            fit: .scaleDown,
            child: Text(text, style: style),
          ),
        ),
      ),
    );
  }
}
