import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A media card slider that previews while dragging and commits on release;
/// the seek variant draws a waveform track.
class MediaSlider extends StatefulWidget {
  const MediaSlider({
    super.key,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.onCommit,
    this.seek = false,
    this.wave = false,
    this.live = false,
  });

  final String label;
  final double value;
  final String Function(double) displayValue;
  final ValueChanged<double>? onCommit;
  final bool seek;
  final bool wave;
  final bool live;

  @override
  State<MediaSlider> createState() => _State();
}

class _State extends State<MediaSlider> {
  double? _drag;
  ({double value, DateTime committed})? _pending;
  Timer? _pendingTimer;
  Timer? _liveTimer;
  double? _trailing;

  @override
  void didUpdateWidget(covariant MediaSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pending case final pending?) {
      if ((widget.value - pending.value).abs() <= 0.005 ||
          DateTime.now().difference(pending.committed) >=
              const Duration(milliseconds: 1500)) {
        _pending = null;
        _pendingTimer?.cancel();
      }
    }
  }

  void _changed(double value) {
    setState(() => _drag = value);
    if (!widget.live) return;
    if (_liveTimer != null) {
      _trailing = value;
      return;
    }
    widget.onCommit?.call(value);
    _liveTimer = Timer(const Duration(milliseconds: 60), _sendTrailing);
  }

  void _sendTrailing() {
    _liveTimer = null;
    final value = _trailing;
    _trailing = null;
    if (value == null) return;
    widget.onCommit?.call(value);
    _liveTimer = Timer(const Duration(milliseconds: 60), _sendTrailing);
  }

  void _committed(double value) {
    _liveTimer?.cancel();
    _liveTimer = null;
    _trailing = null;
    _pendingTimer?.cancel();
    setState(() {
      _drag = null;
      _pending = (value: value, committed: DateTime.now());
    });
    _pendingTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() => _pending = null);
    });
    widget.onCommit?.call(value);
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seek = widget.seek;
    final active = seek && Theme.of(context).brightness == .light
        ? colors.onPrimaryContainer
        : colors.primary;
    final inactive = seek
        ? Color.alphaBlend(
            colors.onPrimary.withValues(alpha: 0.65),
            colors.primaryContainer,
          )
        : colors.secondaryContainer;
    return Semantics(
      label: widget.label,
      child: SizedBox(
        height: seek ? 24 : 32,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: seek ? 8 : 16,
            trackGap: seek ? 3 : 6,
            padding: const .symmetric(horizontal: 2),
            trackShape: seek
                ? _SeekTrack(wave: widget.wave)
                : const GappedSliderTrackShape(),
            thumbShape: const HandleThumbShape(),
            thumbSize: .all(Size(4, seek ? 24 : 32)),
            thumbColor: seek ? colors.onPrimaryContainer : active,
            activeTrackColor: active,
            inactiveTrackColor: inactive,
            disabledActiveTrackColor: widget.seek ? active : colors.outline,
            disabledInactiveTrackColor: inactive,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: widget.onCommit == null
                ? widget.value
                : _drag ?? _pending?.value ?? widget.value,
            semanticFormatterCallback: widget.displayValue,
            onChanged: widget.onCommit == null ? null : _changed,
            onChangeEnd: widget.onCommit == null ? null : _committed,
          ),
        ),
      ),
    );
  }
}

class _SeekTrack extends GappedSliderTrackShape {
  const _SeekTrack({required this.wave});

  final bool wave;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (!wave) {
      super.paint(
        context,
        offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        isEnabled: isEnabled,
      );
      return;
    }
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
    );
    final rtl = textDirection == .rtl;
    final width = rect.width;
    final progress =
        (rtl ? rect.right - thumbCenter.dx : thumbCenter.dx - rect.left).clamp(
          0.0,
          width,
        );
    final canvas = context.canvas
      ..save()
      ..translate(rtl ? rect.right : rect.left, rect.center.dy)
      ..scale(rtl ? -1 : 1);
    final start = progress + 3;
    if (start < width) {
      canvas.drawRRect(
        RRect.fromLTRBR(start, -4, width, 4, const Radius.circular(4)),
        Paint()..color = sliderTheme.inactiveTrackColor!,
      );
      if (start < width - 4) {
        canvas.drawCircle(
          Offset(width - 4, 0),
          2,
          Paint()..color = sliderTheme.thumbColor!,
        );
      }
    }
    final end = progress - 3;
    if (end > 0) {
      final path = Path()..moveTo(0, 0);
      for (var x = 1.0; x < end; x++) {
        path.lineTo(x, math.sin(x * math.pi / 20) * 3);
      }
      path.lineTo(end, math.sin(end * math.pi / 20) * 3);
      canvas.drawPath(
        path,
        Paint()
          ..color = sliderTheme.activeTrackColor!
          ..style = .stroke
          ..strokeWidth = 8
          ..strokeCap = .round,
      );
    }
    canvas.restore();
  }
}
