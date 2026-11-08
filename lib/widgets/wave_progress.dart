import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// An expressive wavy determinate track with a gap and stop dot.
class WaveProgressPainter extends CustomPainter {
  const WaveProgressPainter({
    required this.fraction,
    required this.active,
    required this.track,
    this.thickness = 8,
    this.amplitude = 3,
  });

  final double fraction;
  final Color active;
  final Color track;
  final double thickness;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = thickness / 2;
    if (size.width <= 2 * radius) return;
    final y = size.height / 2;
    final end = size.width - radius;
    final filled = radius + (end - radius) * fraction;
    final paint = Paint()
      ..strokeWidth = 2 * radius
      ..strokeCap = .round;
    final trackStart = fraction == 0 ? radius : filled + 2 * radius + 4;
    if (trackStart <= end) {
      canvas.drawLine(
        Offset(trackStart, y),
        Offset(end, y),
        paint..color = track,
      );
      canvas.drawCircle(Offset(end, y), 2, paint..color = active);
    }
    if (fraction == 0) return;
    final wave = Path()..moveTo(radius, y);
    for (var x = radius + 1; x < filled; x++) {
      wave.lineTo(x, y + amplitude * math.sin((x - radius) * math.pi / 20));
    }
    wave.lineTo(
      filled,
      y + amplitude * math.sin((filled - radius) * math.pi / 20),
    );
    canvas.drawPath(
      wave,
      paint
        ..color = active
        ..style = .stroke,
    );
  }

  @override
  bool shouldRepaint(WaveProgressPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      active != oldDelegate.active ||
      track != oldDelegate.track ||
      thickness != oldDelegate.thickness ||
      amplitude != oldDelegate.amplitude;
}
