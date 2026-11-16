import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/widgets/bar_groups_layout.dart';
import 'package:remya_bar/widgets/bar_pill_slot.dart';

Widget _bar(Widget? pill) => Directionality(
  textDirection: .ltr,
  child: Center(
    child: SizedBox(
      height: 40,
      child: BarGroupsLayout(
        center: 0,
        children: [
          Row(
            mainAxisSize: .min,
            children: [
              const BarPillSlot(child: SizedBox(key: Key('a'), width: 50)),
              BarPillSlot(leading: true, child: pill),
            ],
          ),
          const Row(mainAxisSize: .min, children: [BarPillSlot()]),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('hidden pills collapse smoothly before unmounting', (
    tester,
  ) async {
    const pill = SizedBox(key: Key('b'), width: 100);
    await tester.pumpWidget(_bar(pill));
    final row = find.byType(Row).first;
    expect(tester.getSize(row).width, 158);

    await tester.pumpWidget(_bar(null));
    await tester.pump(BarPillSlot.duration ~/ 2);
    expect(find.byKey(const Key('b')), findsOneWidget);
    final mid = tester.getSize(row).width;
    expect(mid, inExclusiveRange(50, 158));

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('b')), findsNothing);
    expect(tester.getSize(row).width, 50);

    await tester.pumpWidget(_bar(pill));
    await tester.pump(BarPillSlot.duration ~/ 2);
    expect(tester.getSize(row).width, inExclusiveRange(50, 158));
    await tester.pumpAndSettle();
    expect(tester.getSize(row).width, 158);
  });

  testWidgets('pill width changes animate', (tester) async {
    Widget sized(double width) => _bar(SizedBox(width: width));
    await tester.pumpWidget(sized(100));
    await tester.pumpWidget(sized(200));
    await tester.pump(BarPillSlot.duration ~/ 2);
    final row = find.byType(Row).first;
    expect(tester.getSize(row).width, inExclusiveRange(158, 258));
    await tester.pumpAndSettle();
    expect(tester.getSize(row).width, 258);
  });

  testWidgets('fading groups move neighbours continuously', (tester) async {
    // Right side of a centered bar: [A] [center] [B] [C], C fading.
    Future<double> rightOf(double width, double presence) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: Align(
            alignment: .topLeft,
            child: SizedBox(
              width: 700,
              height: 40,
              child: BarGroupsLayout(
                center: 1,
                children: [
                  for (final (i, (w, p)) in [
                    (50.0, 1.0),
                    (100.0, 1.0),
                    (60.0, 1.0),
                    (width, presence),
                  ].indexed)
                    BarGroupPresence(
                      presence: p,
                      child: SizedBox(key: ValueKey(i), width: w),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byKey(const ValueKey(2))).dx;
    }

    final shown = await rightOf(80, 1);
    final half = await rightOf(40, .5);
    final gone = await rightOf(0, 0);
    // A lone right group sits at the end; a vanishing one leaves it there.
    expect(gone, 700 - 60);
    expect(await rightOf(1e-6, 1e-6), closeTo(gone, .01));
    expect(half, inExclusiveRange(shown, gone));
  });
}
