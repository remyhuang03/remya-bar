import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';

import 'ai_usage_data.dart';

class AiQuotaRing extends StatelessWidget {
  const AiQuotaRing(
    this.provider, {
    super.key,
    required this.showUsed,
    this.ringOrder = '5h-outer',
    this.index = 0,
  });

  final AiQuotaProvider provider;
  final bool showUsed;
  final String ringOrder;

  /// Position among the shown providers; picks the fallback accent.
  final int index;

  /// Assigns up to two quota windows to the outer and inner rings per [ringOrder].
  ({AiQuotaWindow? outer, AiQuotaWindow? inner}) resolveWindows() {
    final windows = provider.pillWindows;
    if (windows.length < 2) return (outer: windows.firstOrNull, inner: null);
    final [first, second] = windows;
    final shortFirst = switch ((first.cadence, second.cadence)) {
      ('5H', _) || (_, '1W') => true,
      (_, '5H') || ('1W', _) => false,
      _ =>
        (aiNumber(first.data['minutes']) ?? double.infinity) <=
            (aiNumber(second.data['minutes']) ?? double.infinity),
    };
    return shortFirst == (ringOrder != '5h-inner')
        ? (outer: first, inner: second)
        : (outer: second, inner: first);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (:outer, :inner) = resolveWindows();
    final tightest = provider.tightest;
    final exhausted = tightest?.left == 0;
    final accent = aiProviderAccent(provider.id, scheme, index: index);
    return _RingPulse(
      low: tightest?.low == true,
      child: SizedBox.square(
        dimension: 28,
        child: Stack(
          fit: .expand,
          children: [
            if (exhausted)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: .circle,
                  color: scheme.errorContainer,
                ),
              ),
            _AnimatedArc(outer, 12.5, 3, accent, showUsed: showUsed),
            if (inner != null)
              _AnimatedArc(inner, 9, 2, accent, showUsed: showUsed),
            Center(
              child: Opacity(
                opacity: exhausted ? .38 : 1,
                child: AiProviderLogo(
                  provider,
                  size: 16,
                  color: exhausted ? scheme.onErrorContainer : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The provider's brand logo, or its initials when no icon is known.
class AiProviderLogo extends StatelessWidget {
  const AiProviderLogo(
    this.provider, {
    super.key,
    required this.size,
    required this.color,
  });

  final AiQuotaProvider provider;
  final double size;

  /// Fills monochrome logos and initials; color logos keep their colors.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      String.fromCharCodes(provider.name.toUpperCase().runes.take(2)),
      textScaler: TextScaler.noScaling,
      style: TextStyle(fontSize: size * .56, fontWeight: .w700, color: color),
    );
    return switch (aiProviderIcon(provider.id)) {
      final asset? => SvgPicture.asset(
        asset,
        width: size,
        height: size,
        theme: SvgTheme(currentColor: color),
        errorBuilder: (_, _, _) => fallback,
      ),
      null => fallback,
    };
  }
}

class _RingPulse extends StatefulWidget {
  const _RingPulse({required this.low, required this.child});

  final bool low;
  final Widget child;

  @override
  State<_RingPulse> createState() => _RingPulseState();
}

class _RingPulseState extends State<_RingPulse>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void didUpdateWidget(_RingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.low &&
        widget.low &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: widget.child,
    builder: (context, child) => Transform.scale(
      scale: MediaQuery.disableAnimationsOf(context)
          ? 1
          : 1 + .10 * math.sin(_pulse.value * math.pi),
      child: child,
    ),
  );
}

class _RingSpring extends Curve {
  const _RingSpring();

  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: .8),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) => _spring.x(t * .36);
}

class _AnimatedArc extends StatelessWidget {
  const _AnimatedArc(
    this.window,
    this.radius,
    this.stroke,
    this.accent, {
    required this.showUsed,
  });

  final AiQuotaWindow? window;
  final double radius;
  final double stroke;
  final Color accent;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = (window?.used ?? 0) / 100;
    final track = window == null
        ? scheme.outlineVariant
        : scheme.onSurface.withValues(alpha: .16);
    final highlight = window?.low == true ? scheme.error : accent;
    final usedColor = showUsed && window != null ? highlight : track;
    final remainingColor = !showUsed && window != null ? highlight : track;
    return TweenAnimationBuilder<double>(
      key: ValueKey((radius, window?.slot, window?.reset)),
      tween: Tween(begin: 0, end: used),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
      curve: const _RingSpring(),
      builder: (_, fill, _) => CustomPaint(
        painter: _ArcPainter(
          radius,
          stroke,
          fill.clamp(0.0, 1.0),
          remainingColor,
          usedColor,
          scheme.onSurface,
          scheme.surfaceContainerHighest,
          window?.expectedUsedFraction,
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(
    this.radius,
    this.stroke,
    this.used,
    this.remainingColor,
    this.usedColor,
    this.tick,
    this.halo,
    this.pace,
  );

  final double radius, stroke, used;
  final Color remainingColor, usedColor, tick, halo;
  final double? pace;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(.zero);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;
    const full = 2 * math.pi;
    final paint = Paint()
      ..style = .stroke
      ..strokeWidth = stroke
      ..strokeCap = .round;
    final angle = used * full;
    final gap = (stroke + 1) / radius;
    if (used < 1) {
      final trim = used == 0 ? 0.0 : gap;
      canvas.drawArc(
        bounds,
        start + angle + trim,
        math.max(0, full - angle - trim * 2),
        false,
        paint..color = remainingColor,
      );
    }
    if (used > 0) {
      canvas.drawArc(bounds, start, angle, false, paint..color = usedColor);
    }
    if (pace case final fraction?) {
      final target = start + fraction * full;
      final unit = Offset(math.cos(target), math.sin(target));
      // A surface halo under a 2px tick keeps it visible on fill and track.
      final from = center + unit * (radius - stroke / 2 - 1.5);
      final to = center + unit * (radius + stroke / 2 + 1.5);
      canvas
        ..drawLine(
          from,
          to,
          Paint()
            ..color = halo
            ..strokeWidth = 4
            ..strokeCap = .round,
        )
        ..drawLine(
          from,
          to,
          Paint()
            ..color = tick
            ..strokeWidth = 2
            ..strokeCap = .round,
        );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      (radius, stroke, used, remainingColor, usedColor, tick, halo, pace) !=
      (
        oldDelegate.radius,
        oldDelegate.stroke,
        oldDelegate.used,
        oldDelegate.remainingColor,
        oldDelegate.usedColor,
        oldDelegate.tick,
        oldDelegate.halo,
        oldDelegate.pace,
      );
}
