import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/clock/calendar_grid.dart';

void main() {
  testWidgets('selects on the first click and opens on a double-click', (
    tester,
  ) async {
    final today = DateTime.utc(2026, 11, 23);
    final tomorrow = DateTime.utc(2026, 11, 24);
    var selected = today;
    final opened = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 372,
              child: StatefulBuilder(
                builder: (context, setState) => CalendarGrid(
                  today: today,
                  selected: selected,
                  firstWeekday: DateTime.monday,
                  cutoffWeekday: DateTime.thursday,
                  week: true,
                  showWeekNumbers: true,
                  events: const [],
                  onSelect: (day) => setState(() => selected = day),
                  onOpenDay: opened.add,
                  onToggle: () {},
                  onAgenda: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final colors = Theme.of(tester.element(find.text('23'))).colorScheme;
    Finder dayDisc(String day) => find.ancestor(
      of: find.text(day),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox && widget.decoration is ShapeDecoration,
      ),
    );
    ShapeDecoration disc(String day) =>
        tester.widget<DecoratedBox>(dayDisc(day)).decoration as ShapeDecoration;
    expect(disc('23').shape, isA<MaterialShapeBorder>());
    expect(disc('23').color, colors.primary);
    Finder focusOutline(String day) => find.descendant(
      of: dayDisc(day),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.foregroundPainter != null,
      ),
    );
    expect(focusOutline('23'), findsNothing);

    await tester.tap(find.text('24'), kind: .mouse);
    await tester.pump();
    expect(selected, tomorrow);
    expect(opened, isEmpty);
    expect(focusOutline('24'), findsNothing);
    expect(disc('23').shape, isA<MaterialShapeBorder>());
    expect(disc('24').color, colors.primary.withValues(alpha: .12));
    expect(
      (disc('24').shape as CircleBorder).side,
      BorderSide(color: colors.primary, width: 1.5),
    );
    expect(tester.widget<Text>(find.text('24')).style?.color, colors.primary);
    expect(
      tester.widget<Text>(find.text('24')).style?.fontWeight,
      FontWeight.w600,
    );

    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('24'), kind: .mouse);
    await tester.pump();
    expect(opened, [tomorrow]);

    await tester.tap(find.text('23'), kind: .mouse);
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(find.text('23'), kind: .mouse);
    await tester.pump(kDoubleTapTimeout);
    expect(selected, today);
    expect(opened, [tomorrow]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusOutline('24'), findsOneWidget);
    await tester.tap(find.text('23'), kind: .mouse);
    await tester.pump(kDoubleTapTimeout);
    expect(focusOutline('23'), findsNothing);
  });
}
