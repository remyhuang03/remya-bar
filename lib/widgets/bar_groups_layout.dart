import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Lays out pill groups at their natural widths.
///
/// When the groups fit [BoxConstraints.minWidth] they are spaced evenly, or
/// split around the [center] group into two evenly spaced sides. Otherwise
/// they sit [gap] apart and the box grows, for a horizontal scroll view.
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

class _GroupParentData extends ContainerBoxParentData<RenderBox> {}

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
    double need(Iterable<double> sizes) => sizes.isEmpty
        ? 0
        : sizes.reduce((a, b) => a + b) + _gap * (sizes.length - 1);
    final available = constraints.minWidth;
    final total = need(widths);
    final center = _center;
    final xs = List.filled(children.length, 0.0);

    // Spreads [range] across [start, end]; a lone group sits at [single].
    void spread(int from, int to, double start, double end, double single) {
      final count = to - from;
      if (count == 0) return;
      if (count == 1) {
        xs[from] = start + (end - start - widths[from]) * single;
        return;
      }
      final free =
          end - start - need(widths.sublist(from, to)) + _gap * (count - 1);
      var x = start;
      for (var i = from; i < to; i++) {
        xs[i] = x;
        x += widths[i] + free / (count - 1);
      }
    }

    final centerFits =
        center != null &&
        center < children.length &&
        math.max(
                      need(widths.sublist(0, center)),
                      need(widths.sublist(center + 1)),
                    ) *
                    2 +
                widths[center] +
                _gap * 2 <=
            available;
    final width = math.max(available, total);
    if (centerFits) {
      final left = (available - widths[center]) / 2;
      xs[center] = left;
      spread(0, center, 0, left - _gap, 0);
      spread(
        center + 1,
        children.length,
        left + widths[center] + _gap,
        available,
        1,
      );
    } else if (total <= available) {
      spread(0, children.length, 0, available, .5);
    } else {
      spread(0, children.length, 0, total, 0);
    }
    for (var i = 0; i < children.length; i++) {
      (children[i].parentData! as _GroupParentData).offset = Offset(
        xs[i],
        (height - children[i].size.height) / 2,
      );
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
