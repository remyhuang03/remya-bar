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

  @override
  void performLayout() {
    super.performLayout();
    if (_height == size.height) return;
    _height = size.height;
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
