import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';

void main() {
  const body = Rect.fromLTWH(40, 12, 420, 300);

  test('neck spans the pill and joins the body with concave fillets', () {
    final path = attachedCardPath(body, 180, 140);
    expect(path.getBounds(), const Rect.fromLTRB(40, 0, 460, 312));
    expect(path.contains(const Offset(181, 1)), isTrue);
    expect(path.contains(const Offset(319, 1)), isTrue);
    expect(path.contains(const Offset(179, 1)), isFalse);
    expect(path.contains(const Offset(321, 1)), isFalse);
    expect(path.contains(const Offset(177, 9)), isTrue);
    expect(path.contains(const Offset(169, 1)), isFalse);
    expect(path.contains(body.center), isTrue);
  });

  test('fillets shrink near a corner and necks merge at window edges', () {
    for (final left in [0.0, 41.0, 74.0, 318.0, 359.0, 360.0]) {
      final path = attachedCardPath(body, left, 140);
      expect(path.contains(Offset(left + 1, 1)), isTrue);
      expect(path.contains(Offset(left + 139, 1)), isTrue);
      expect(path.contains(Offset(left + 70, 13)), isTrue);
      expect(path.contains(body.center), isTrue);
      expect(path.getBounds().left, greaterThanOrEqualTo(0));
      expect(path.getBounds().right, lessThanOrEqualTo(500));
      // No fillet may escape the window above the body's rounded corners.
      expect(path.contains(const Offset(-1, 11)), isFalse);
      expect(path.contains(const Offset(501, 11)), isFalse);
    }
    final clamped = attachedCardPath(body, 74, 140);
    expect(clamped.contains(const Offset(71, 10)), isFalse);
    expect(clamped.contains(const Offset(73.5, 11.5)), isTrue);
  });

  test('zero progress is the pill footprint and width leads height', () {
    final collapsed = attachedCardPath(body, 180, 140, progress: 0);
    expect(collapsed.getBounds(), const Rect.fromLTWH(180, 12, 140, 0));
    for (final t in [.01, .2, .5, .9]) {
      final path = attachedCardPath(body, 180, 140, progress: t);
      final bounds = path.getBounds();
      expect(bounds.bottom, closeTo(body.top + body.height * t, .001));
      expect(bounds.width, greaterThan(140 + (420 - 140) * t));
      expect(path.contains(Offset(250, 12 + body.height * t / 2)), isTrue);
    }
  });
}
