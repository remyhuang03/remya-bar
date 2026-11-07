import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The body emerges from the pill without changing the popup's layout size.
Path attachedCardPath(
  Rect body,
  double pillLeft,
  double pillWidth, {
  double neckTop = 0,
  double radius = 32,
  double fillet = 12,
  double progress = 1,
}) {
  final t = progress.clamp(0.0, 1.0);
  final footprint = Rect.fromLTWH(pillLeft, body.top, pillWidth, 0);
  if (t == 0) return Path()..addRect(footprint);
  final widthProgress = math.pow(t, .7).toDouble();
  final rect = Rect.fromLTRB(
    footprint.left + (body.left - footprint.left) * widthProgress,
    body.top,
    footprint.right + (body.right - footprint.right) * widthProgress,
    body.top + body.height * t,
  );
  final r = math.min(
    math.max(16, radius * t),
    math.min(rect.width, rect.height) / 2,
  );
  final top = neckTop;
  final right = pillLeft + pillWidth;
  final f = math.min(fillet * t, rect.top - top);
  final leftFillet = math.min(f, math.max(0.0, pillLeft - rect.left - r));
  final rightFillet = math.min(f, math.max(0.0, rect.right - r - right));
  final path = Path()
    ..moveTo(pillLeft, top)
    ..lineTo(right, top)
    ..lineTo(right, rect.top - rightFillet);
  if (rightFillet > 0) {
    path.arcToPoint(
      Offset(right + rightFillet, rect.top),
      radius: Radius.circular(rightFillet),
      clockwise: false,
    );
  }
  if (right <= rect.right - r) path.lineTo(rect.right - r, rect.top);
  path
    ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r)
    ..lineTo(rect.right, rect.bottom - r)
    ..quadraticBezierTo(rect.right, rect.bottom, rect.right - r, rect.bottom)
    ..lineTo(rect.left + r, rect.bottom)
    ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - r)
    ..lineTo(rect.left, rect.top + r)
    ..quadraticBezierTo(
      rect.left,
      rect.top,
      pillLeft >= rect.left + r ? rect.left + r : pillLeft,
      rect.top,
    );
  if (pillLeft >= rect.left + r) path.lineTo(pillLeft - leftFillet, rect.top);
  if (leftFillet > 0) {
    path.arcToPoint(
      Offset(pillLeft, rect.top - leftFillet),
      radius: Radius.circular(leftFillet),
      clockwise: false,
    );
  }
  return path
    ..lineTo(pillLeft, top)
    ..close();
}

class BarCardSurface extends StatelessWidget {
  const BarCardSurface({
    super.key,
    required this.child,
    this.seedColor,
    this.styleVariant = .tonalSpot,
    this.pill,
    this.emergence = const AlwaysStoppedAnimation(1),
  });

  final Widget child;
  final Color? seedColor;
  final DynamicSchemeVariant styleVariant;
  final Rect? pill;
  final Animation<double> emergence;

  // The top inset is the neck; the other insets reserve shadow room.
  static const shadowInsets = EdgeInsets.fromLTRB(40, 12, 40, 52);

  static ColorScheme colors(
    ThemeData theme,
    Color? seed,
    DynamicSchemeVariant variant,
  ) => seed == null
      ? theme.colorScheme
      : ColorScheme.fromSeed(
          seedColor: seed,
          brightness: theme.brightness,
          dynamicSchemeVariant: variant,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = colors(theme, seedColor, styleVariant);
    return Theme(
      data: theme.copyWith(colorScheme: scheme),
      child: AnimatedBuilder(
        animation: emergence,
        child: Padding(
          padding: shadowInsets,
          child: Material(
            type: .transparency,
            child: SingleChildScrollView(padding: const .all(24), child: child),
          ),
        ),
        builder: (context, child) {
          final progress = emergence.value.clamp(0.0, 1.0);
          final clipper = _CardClipper(pill, progress);
          return CustomPaint(
            painter: _CardPainter(clipper, scheme.surfaceContainer),
            child: ClipPath(
              clipper: clipper,
              child: Opacity(
                opacity: ((progress - .45) / .55).clamp(0.0, 1.0),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardClipper extends CustomClipper<Path> {
  const _CardClipper(this.pill, this.progress);
  final Rect? pill;
  final double progress;

  @override
  Path getClip(Size size) {
    final body = BarCardSurface.shadowInsets.deflateRect(Offset.zero & size);
    final anchor = pill;
    return anchor == null
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(body, const Radius.circular(32)),
          ))
        : attachedCardPath(body, anchor.left, anchor.width, progress: progress);
  }

  @override
  bool shouldReclip(_CardClipper oldClipper) =>
      pill != oldClipper.pill || progress != oldClipper.progress;
}

class _CardPainter extends CustomPainter {
  const _CardPainter(this.clipper, this.color);
  final _CardClipper clipper;
  final Color color;
  static const _shadow = BoxShadow(
    color: Color(0x66000000),
    offset: Offset(0, 12),
    blurRadius: 20,
    spreadRadius: 8,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (clipper.progress == 0) return;
    final path = clipper.getClip(size);
    // Keep the neck and bar seam free of shadow above the body.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 12, size.width, size.height));
    final shadow = path.shift(_shadow.offset);
    canvas.drawPath(
      shadow,
      _shadow.toPaint()
        ..style = .stroke
        ..strokeWidth = _shadow.spreadRadius * 2
        ..strokeJoin = .round,
    );
    canvas.drawPath(shadow, _shadow.toPaint());
    canvas.restore();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CardPainter oldDelegate) =>
      color != oldDelegate.color || clipper.shouldReclip(oldDelegate.clipper);
}
