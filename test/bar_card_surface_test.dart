import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/popups/popup_measure.dart';
import 'package:remya_ui/remya_ui.dart';

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

  test('a pill wider than the body tapers into it without square corners', () {
    final path = attachedCardPath(body, 20, 480);
    expect(path.contains(const Offset(21, 1)), isTrue);
    expect(path.contains(const Offset(499, 1)), isTrue);
    // The old step left a square corner under each pill end at the body top.
    expect(path.contains(const Offset(499, 13)), isFalse);
    expect(path.contains(const Offset(21, 13)), isFalse);
    expect(path.contains(const Offset(492, 13)), isTrue);
    expect(path.contains(const Offset(459, 44)), isTrue);
    expect(path.contains(const Offset(461, 44)), isFalse);
    expect(path.contains(body.center), isTrue);
  });

  test('body shifts under a pill clamped at a screen edge', () {
    const width = 500.0;
    expect(BarCardSurface.insetsFor(null, width), BarCardSurface.shadowInsets);
    final centered = BarCardSurface.insetsFor(
      const Rect.fromLTWH(200, 0, 50, 0),
      width,
    );
    expect(centered, BarCardSurface.shadowInsets);
    final left = BarCardSurface.insetsFor(
      const Rect.fromLTWH(24, 0, 50, 0),
      width,
    );
    expect((left.left, left.right), (24, 56));
    final right = BarCardSurface.insetsFor(
      const Rect.fromLTWH(430, 0, 60, 0),
      width,
    );
    expect((left.horizontal, right.left, right.right), (80, 70, 10));
  });

  test('a bottom bar moves the neck under the body', () {
    const width = 500.0;
    final top = BarCardSurface.insetsFor(
      const Rect.fromLTWH(24, 0, 50, 0),
      width,
    );
    final bottom = BarCardSurface.insetsFor(
      const Rect.fromLTWH(24, 0, 50, 0),
      width,
      bottom: true,
    );
    expect(
      (bottom.left, bottom.right, bottom.top, bottom.bottom),
      (top.left, top.right, top.bottom, top.top),
    );
  });

  testWidgets('strips outer shadow padding from descendant MediaQuery', (
    tester,
  ) async {
    late EdgeInsets childPadding;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.fromLTRB(40, 36, 44, 76),
          ),
          child: BarPopupScope(
            theme: const RemyaTheme(),
            child: Center(
              child: SizedBox(
                width: 452,
                height: 674,
                child: BarCardSurface(
                  styleVariant: .tonalSpot,
                  child: Builder(
                    builder: (context) {
                      childPadding = MediaQuery.paddingOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(childPadding, EdgeInsets.zero);
  });

  testWidgets('a clamped card scrolls its body under a fixed header', (
    tester,
  ) async {
    double? natural;
    await tester.pumpWidget(
      MaterialApp(
        home: BarPopupScope(
          theme: const RemyaTheme(),
          child: Align(
            alignment: .topCenter,
            child: SizedBox(
              width: 500,
              height: 400,
              child: PopupMeasure(
                onHeight: (height) => natural = height,
                child: BarCardSurface(
                  pill: const Rect.fromLTWH(200, 0, 100, 0),
                  child: BarCardSections(
                    header: const Text('Title'),
                    children: [
                      for (var i = 0; i < 20; i++)
                        SizedBox(height: 60, child: Text('Row $i')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The window asks for the whole content, but only the body scrolls.
    expect(natural, greaterThan(1200));
    final title = tester.getTopLeft(find.text('Title'));
    final row = tester.getTopLeft(find.text('Row 0'));
    await tester.drag(find.text('Row 2'), const Offset(0, -200));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Title')), title);
    expect(tester.getTopLeft(find.text('Row 0')).dy, lessThan(row.dy - 100));
  });
}
