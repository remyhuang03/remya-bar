import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'package:material_ui/material_ui.dart';

import 'bar_popup.dart';

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
  // A pill reaching past the body's rounded corner tapers into the body side
  // with an S-curve instead of meeting it at a right angle.
  final taperTop = rect.top - f;
  final taperBottom = rect.top + r;
  final taperMid = (taperTop + taperBottom) / 2;
  final rightTaper = right > rect.right - r;
  final leftTaper = pillLeft < rect.left + r;
  final leftFillet = math.min(f, math.max(0.0, pillLeft - rect.left - r));
  final rightFillet = math.min(f, math.max(0.0, rect.right - r - right));
  final path = Path()
    ..moveTo(pillLeft, top)
    ..lineTo(right, top);
  if (rightTaper) {
    path
      ..lineTo(right, taperTop)
      ..cubicTo(right, taperMid, rect.right, taperMid, rect.right, taperBottom);
  } else {
    path.lineTo(right, rect.top - rightFillet);
    if (rightFillet > 0) {
      path.arcToPoint(
        Offset(right + rightFillet, rect.top),
        radius: Radius.circular(rightFillet),
        clockwise: false,
      );
    }
    path
      ..lineTo(rect.right - r, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r);
  }
  path
    ..lineTo(rect.right, rect.bottom - r)
    ..quadraticBezierTo(rect.right, rect.bottom, rect.right - r, rect.bottom)
    ..lineTo(rect.left + r, rect.bottom)
    ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - r)
    ..lineTo(rect.left, rect.top + r);
  if (leftTaper) {
    return path
      ..cubicTo(rect.left, taperMid, pillLeft, taperMid, pillLeft, taperTop)
      ..lineTo(pillLeft, top)
      ..close();
  }
  path
    ..quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top)
    ..lineTo(pillLeft - leftFillet, rect.top);
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

/// A card's content: a [header] that stays put and [children] that scroll
/// below it once the popup reaches its maximum height.
class BarCardSections extends StatelessWidget {
  const BarCardSections({
    super.key,
    this.header,
    required this.children,
    this.spacing = 16,
  });

  final Widget? header;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => _PinnedHeader(
    children: [
      if (header case final header?)
        Padding(padding: const .fromLTRB(24, 24, 24, 0), child: header)
      else
        const SizedBox.shrink(),
      MediaQuery(
        // Material scrollbars inset their track by the MediaQuery padding.
        data: MediaQuery.of(context)
            .copyWith(padding: const .only(right: 4, bottom: 24)),
        child: SingleChildScrollView(
          padding: .fromLTRB(24, header == null ? 24 : spacing, 24, 24),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: spacing,
            children: children,
          ),
        ),
      ),
    ],
  );
}

/// Lays out a fixed first child above a second child that gets the remaining
/// height, or its natural height under unbounded constraints.
class _PinnedHeader extends MultiChildRenderObjectWidget {
  const _PinnedHeader({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPinnedHeader();
}

class _PinnedHeaderData extends ContainerBoxParentData<RenderBox> {}

class _RenderPinnedHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PinnedHeaderData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PinnedHeaderData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PinnedHeaderData) {
      child.parentData = _PinnedHeaderData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final body = childAfter(header)!;
    final width = BoxConstraints.tightFor(width: constraints.maxWidth);
    header.layout(width, parentUsesSize: true);
    final top = header.size.height;
    body.layout(
      width.copyWith(maxHeight: math.max(0.0, constraints.maxHeight - top)),
      parentUsesSize: true,
    );
    (body.parentData! as _PinnedHeaderData).offset = Offset(0, top);
    size = constraints.constrain(
      Size(constraints.maxWidth, top + body.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class BarCardSurface extends StatelessWidget {
  const BarCardSurface({
    super.key,
    required this.child,
    this.seedColor,
    this.styleVariant = .tonalSpot,
    this.pill,
    this.emergence = const AlwaysStoppedAnimation(1),
    this.bodyWidth,
  });

  final Widget child;
  final Color? seedColor;
  final DynamicSchemeVariant styleVariant;
  final Rect? pill;
  final Animation<double> emergence;
  final double? bodyWidth;

  // The top inset is the neck; the other insets reserve shadow room.
  static const shadowInsets = EdgeInsets.fromLTRB(40, 12, 40, 52);

  /// Near a screen edge the popup is clamped while the pill is not, so the body
  /// shifts into the shadow room to stay under its pill. A bottom bar puts the
  /// neck at the bottom.
  static EdgeInsets insetsFor(
    Rect? pill,
    double width, {
    bool bottom = false,
    double? bodyWidth,
  }) {
    final side = bodyWidth == null
        ? shadowInsets.left
        : ((width - bodyWidth) / 2).clamp(0.0, shadowInsets.left);
    final insets = _shifted(pill, width, side);
    return bottom
        ? insets.copyWith(top: insets.bottom, bottom: insets.top)
        : insets;
  }

  static EdgeInsets _shifted(Rect? pill, double width, double side) {
    final insets = shadowInsets.copyWith(left: side, right: side);
    if (pill == null) return insets;
    final left = side;
    final right = width - side;
    final shift = pill.left < left
        ? pill.left - left
        : pill.right > right
        ? pill.right - right
        : 0.0;
    final dx = shift.clamp(-side, side);
    return insets.copyWith(left: left + dx, right: side - dx);
  }

  static ColorScheme colors(
    ThemeData theme,
    Color? seed,
    DynamicSchemeVariant variant, {
    double contrastLevel = 0,
  }) => seed == null
      ? theme.colorScheme
      : ColorScheme.fromSeed(
          seedColor: seed,
          brightness: theme.brightness,
          dynamicSchemeVariant: variant,
          contrastLevel: contrastLevel,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = colors(
      theme,
      seedColor,
      styleVariant,
      contrastLevel: BarPopupScope.contrastOf(context),
    );
    final bottom = BarPopupScope.bottomOf(context);
    return Theme(
      data: theme.copyWith(colorScheme: scheme),
      child: AnimatedBuilder(
        animation: emergence,
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: insetsFor(
              pill,
              constraints.maxWidth,
              bottom: bottom,
              bodyWidth: bodyWidth,
            ),
            // Strip the popup's shadow insets so scrollables inside the card
            // keep their scrollbars aligned with the content.
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeTop: true,
              removeRight: true,
              removeBottom: true,
              child: Material(type: .transparency, child: child),
            ),
          ),
        ),
        builder: (context, child) {
          final progress = emergence.value.clamp(0.0, 1.0);
          final clipper = _CardClipper(pill, progress, bottom, bodyWidth);
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
  const _CardClipper(this.pill, this.progress, this.bottom, this.bodyWidth);
  final Rect? pill;
  final double progress;
  final bool bottom;
  final double? bodyWidth;

  @override
  Path getClip(Size size) {
    // Built for a top bar, then mirrored so a bottom card grows upwards.
    final body = BarCardSurface.insetsFor(
      pill,
      size.width,
      bodyWidth: bodyWidth,
    ).deflateRect(Offset.zero & size);
    final anchor = pill;
    final path = anchor == null
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(body, const Radius.circular(32)),
          ))
        : attachedCardPath(body, anchor.left, anchor.width, progress: progress);
    if (!bottom) return path;
    return path.transform(
      (Matrix4.translationValues(
        0,
        size.height,
        0,
      )..scaleByDouble(1, -1, 1, 1)).storage,
    );
  }

  @override
  bool shouldReclip(_CardClipper oldClipper) =>
      pill != oldClipper.pill ||
      progress != oldClipper.progress ||
      bottom != oldClipper.bottom ||
      bodyWidth != oldClipper.bodyWidth;
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
    canvas.clipRect(
      clipper.bottom
          ? Rect.fromLTRB(0, 0, size.width, size.height - 12)
          : Rect.fromLTRB(0, 12, size.width, size.height),
    );
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
