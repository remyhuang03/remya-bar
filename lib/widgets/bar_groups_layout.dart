import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Lays out pill groups at their natural widths.
///
/// When the groups fit [BoxConstraints.minWidth] they are spaced evenly, or
/// split around the [center] group into two evenly spaced sides. Otherwise
/// they sit [gap] apart and the box grows, for a horizontal scroll view.
///
/// Wrap a child in [BarGroupPresence] to fade it in or out of the spacing:
/// the layout is continuous in presence, so collapsing groups never jump.
class BarGroupsLayout extends MultiChildRenderObjectWidget {
  const BarGroupsLayout({
    super.key,
    required super.children,
    this.center,
    this.gap = 16,
  });

  /// Index into [children] of the centered group, or null.
  final int? center;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBarGroups(center, gap);

  @override
  void updateRenderObject(BuildContext context, RenderBarGroups renderObject) =>
      renderObject
        ..center = center
        ..gap = gap;
}

/// How much a [BarGroupsLayout] child takes part in spacing, from 0 to 1.
class BarGroupPresence extends ParentDataWidget<_GroupParentData> {
  const BarGroupPresence({
    super.key,
    required this.presence,
    required super.child,
  });

  final double presence;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _GroupParentData;
    if (data.presence == presence) return;
    data.presence = presence;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => BarGroupsLayout;
}

class _GroupParentData extends ContainerBoxParentData<RenderBox> {
  double presence = 1;
}

class RenderBarGroups extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GroupParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GroupParentData> {
  RenderBarGroups(this._center, this._gap);

  int? _center;
  set center(int? value) {
    if (value == _center) return;
    _center = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GroupParentData) {
      child.parentData = _GroupParentData();
    }
  }

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final height = constraints.maxHeight;
    for (final child in children) {
      child.layout(BoxConstraints(maxHeight: height), parentUsesSize: true);
    }
    final widths = [for (final child in children) child.size.width];
    final presence = [
      for (final child in children)
        (child.parentData! as _GroupParentData).presence.clamp(0.0, 1.0),
    ];

    // Weight of the gap before each child in [from, to): it fades with the
    // child and only exists once an earlier child is present.
    List<double> gaps(int from, int to) {
      var before = 0.0;
      final weights = <double>[];
      for (var i = from; i < to; i++) {
        weights.add(math.min(presence[i], before));
        before = math.max(before, presence[i]);
      }
      return weights;
    }

    double need(int from, int to) =>
        widths.sublist(from, to).fold(0.0, (a, b) => a + b) +
        _gap * gaps(from, to).fold(0.0, (a, b) => a + b);

    final available = constraints.minWidth;
    final total = need(0, children.length);

    // Spreads [from, to) across [start, end]. With under one gap's worth of
    // presence, the leftover space places the group at [single].
    void spread(
      List<double> xs,
      int from,
      int to,
      double start,
      double end,
      double single,
    ) {
      if (from >= to) return;
      final weights = gaps(from, to);
      final sum = weights.fold(0.0, (a, b) => a + b);
      final free =
          end - start - widths.sublist(from, to).fold(0.0, (a, b) => a + b);
      var x = start + free * math.max(0, 1 - sum) * single;
      for (var i = from; i < to; i++) {
        x += free * weights[i - from] / math.max(1, sum);
        xs[i] = x;
        x += widths[i];
      }
    }

    List<double> evenly() {
      final xs = List.filled(children.length, 0.0);
      if (total <= available) {
        spread(xs, 0, children.length, 0, available, .5);
        return xs;
      }
      // Overflowing groups sit [gap] apart, scaled by presence.
      final weights = gaps(0, children.length);
      var x = 0.0;
      for (var i = 0; i < children.length; i++) {
        x += _gap * weights[i];
        xs[i] = x;
        x += widths[i];
      }
      return xs;
    }

    final center = _center;
    final centerFits =
        center != null &&
        center < children.length &&
        presence[center] > 0 &&
        math.max(need(0, center), need(center + 1, children.length)) * 2 +
                widths[center] +
                _gap * 2 <=
            available;
    var xs = evenly();
    if (centerFits) {
      final centered = List.filled(children.length, 0.0);
      final left = (available - widths[center]) / 2;
      centered[center] = left;
      spread(centered, 0, center, 0, left - _gap, 0);
      spread(
        centered,
        center + 1,
        children.length,
        left + widths[center] + _gap,
        available,
        1,
      );
      xs = [
        for (var i = 0; i < xs.length; i++)
          lerpDouble(xs[i], centered[i], presence[center])!,
      ];
    }
    for (var i = 0; i < children.length; i++) {
      (children[i].parentData! as _GroupParentData).offset = Offset(
        xs[i],
        (height - children[i].size.height) / 2,
      );
    }
    size = constraints.constrain(Size(math.max(available, total), height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
