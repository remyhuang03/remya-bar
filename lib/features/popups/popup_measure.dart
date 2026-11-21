import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class PopupMeasure extends SingleChildRenderObjectWidget {
  const PopupMeasure({
    super.key,
    this.generation = 0,
    required this.onHeight,
    required super.child,
  });
  final int generation;
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PopupMeasureBox(generation, onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _PopupMeasureBox;
    box.onHeight = onHeight;
    if (box.generation != generation) {
      box.generation = generation;
      box.resetMeasurement();
    }
  }
}

class _PopupMeasureBox extends RenderProxyBox {
  _PopupMeasureBox(this.generation, this.onHeight);
  int generation;
  ValueChanged<double> onHeight;
  double? _height;

  void resetMeasurement() {
    _height = null;
    markNeedsLayout();
  }

  // Reports the child's natural height, then fits it into a window that the
  // compositor clamped smaller, so the card body scrolls inside its shape.
  @override
  void performLayout() {
    final child = this.child!;
    final natural = constraints.copyWith(
      minHeight: 0,
      maxHeight: double.infinity,
    );
    child.layout(natural, parentUsesSize: true);
    final height = child.size.height;
    if (height > constraints.maxHeight) {
      child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    }
    size = constraints.constrain(child.size);
    if (_height == height) return;
    _height = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
