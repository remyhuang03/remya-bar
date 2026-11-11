import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'ai_usage_data.dart';

class AiQuotaRing extends StatelessWidget {
  const AiQuotaRing(this.provider, {super.key, required this.showUsed});

  final AiQuotaProvider provider;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inner = provider.window('secondary');
    final outer =
        provider.window('primary') ??
        (inner == null ? provider.window('tertiary') : null);
    final tightest = provider.tightest;
    final exhausted = tightest?.left == 0;
    final color = exhausted
        ? scheme.onErrorContainer
        : tightest?.low == true
        ? scheme.error
        : scheme.onSurface;
    return _RingPulse(
      low: tightest?.low == true,
      child: SizedBox.square(
        dimension: 26,
        child: Stack(
          fit: .expand,
          children: [
            if (exhausted)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: .circle,
                  color: scheme.errorContainer,
                ),
              )
            else ...[
              _AnimatedArc(outer, 11.5, 3, showUsed: showUsed),
              _AnimatedArc(inner, 7.75, 2.5, showUsed: showUsed),
            ],
            Center(child: _ProviderGlyph(provider, color)),
          ],
        ),
      ),
    );
  }
}

class _ProviderGlyph extends StatelessWidget {
  const _ProviderGlyph(this.provider, this.color);

  final AiQuotaProvider provider;
  final Color color;

  static final _assets = AssetManifest.loadFromAssetBundle(rootBundle)
      .then((manifest) => manifest.listAssets().toSet());

  @override
  Widget build(BuildContext context) {
    final icon = switch (provider.id) {
      'alibabatokenplan' => 'alibaba',
      'azureopenai' || 'openai' => 'codex',
      'moonshot' => 'kimi',
      final id => id,
    };
    final asset = 'assets/icons/ai_usage/$icon.svg';
    final fallback = Text(
      String.fromCharCodes(provider.name.toUpperCase().runes.take(2)),
      textScaler: TextScaler.noScaling,
      style: TextStyle(fontSize: 7, fontWeight: .w700, color: color),
    );
    return FutureBuilder<Set<String>>(
      future: _assets,
      builder: (context, snapshot) => snapshot.data?.contains(asset) == true
          ? SvgPicture.asset(
              asset,
              width: 10,
              height: 10,
              colorFilter: ColorFilter.mode(color, .srcIn),
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
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
    this.stroke, {
    required this.showUsed,
  });

  final AiQuotaWindow? window;
  final double radius;
  final double stroke;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = window?.left;
    final expected = window?.expectedLeft;
    return TweenAnimationBuilder<double>(
      key: ValueKey(window?.reset),
      tween: Tween(
        begin: 0,
        end: left == null ? 0 : (showUsed ? 100 - left : left) / 100,
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
      curve: const _RingSpring(),
      builder: (_, fill, _) => CustomPaint(
        painter: _ArcPainter(
          radius,
          stroke,
          fill.clamp(0.0, 1.0),
          left == null ? scheme.outlineVariant : scheme.secondaryContainer,
          window?.low == true ? scheme.error : scheme.primary,
          scheme.onSurface,
          expected == null
              ? null
              : (showUsed ? 100 - expected : expected) / 100,
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(
    this.radius,
    this.stroke,
    this.fill,
    this.track,
    this.active,
    this.tick,
    this.pace,
  );

  final double radius, stroke, fill;
  final Color track, active, tick;
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
    final angle = fill * full;
    final gap = (stroke + 1) / radius;
    if (fill < 1) {
      final trim = fill == 0 ? 0.0 : gap;
      canvas.drawArc(
        bounds,
        start + angle + trim,
        math.max(0, full - angle - trim * 2),
        false,
        paint..color = track,
      );
    }
    if (fill > 0) {
      canvas.drawArc(bounds, start, angle, false, paint..color = active);
    }
    if (pace case final fraction?) {
      final target = start + fraction * full;
      final unit = Offset(math.cos(target), math.sin(target));
      canvas.drawLine(
        center + unit * (radius - stroke / 2),
        center + unit * (radius + stroke / 2),
        Paint()
          ..color = tick
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      (radius, stroke, fill, track, active, tick, pace) !=
      (
        oldDelegate.radius,
        oldDelegate.stroke,
        oldDelegate.fill,
        oldDelegate.track,
        oldDelegate.active,
        oldDelegate.tick,
        oldDelegate.pace,
      );
}
