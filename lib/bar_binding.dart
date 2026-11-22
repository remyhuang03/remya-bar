import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Flutter composites every view each frame; with three wide bar views that
/// made raster cost the bottleneck of any popup animation. Only views with
/// repainted nodes or a new configuration are sent to the engine; the engine
/// keeps presenting the previous frame of the others.
class BarBinding extends BindingBase
    with
        GestureBinding,
        SchedulerBinding,
        ServicesBinding,
        PaintingBinding,
        SemanticsBinding,
        RendererBinding,
        _ChangedViewsOnly,
        WidgetsBinding {
  static WidgetsBinding ensureInitialized() {
    _created ??= BarBinding();
    return WidgetsBinding.instance;
  }

  static BarBinding? _created;
}

mixin _ChangedViewsOnly on RendererBinding {
  final _composited = Expando<ViewConfiguration>();
  bool _framesSent = false;

  @override
  void drawFrame() {
    // The base implementation owns first-frame deferral bookkeeping.
    if (!_framesSent) {
      super.drawFrame();
      _framesSent = sendFramesToEngine;
      for (final view in renderViews) {
        _composited[view] = view.configuration;
      }
      return;
    }
    rootPipelineOwner.flushLayout();
    rootPipelineOwner.flushCompositingBits();
    final changed = <RenderView>{};
    void collect(PipelineOwner owner, RenderView? view) {
      if (owner.rootNode case final RenderView root) view = root;
      // ignore: invalid_use_of_protected_member, read-only dirty check before paint.
      if (view != null && owner.nodesNeedingPaint.isNotEmpty) changed.add(view);
      owner.visitChildren((child) => collect(child, view));
    }

    collect(rootPipelineOwner, null);
    rootPipelineOwner.flushPaint();
    for (final view in renderViews) {
      if (changed.contains(view) ||
          !identical(_composited[view], view.configuration)) {
        _composited[view] = view.configuration;
        view.compositeFrame();
      }
    }
    rootPipelineOwner.flushSemantics();
  }
}
