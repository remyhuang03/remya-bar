import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/system/system_backend.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: .linear(scale)),
    child: Material(child: child),
  ),
);

void main() {
  testWidgets('battery distinguishes charging, low power, unknown and absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BarBattery(
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 100,
            state: 'Charging',
          ),
        ),
        scale: 2,
      ),
    );
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    final fullFillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(fullFillBox.color, const Color(0xFF0AC20A));
    final track = tester.getRect(find.byType(ClipRRect));
    expect(track.width, 48);
    expect(track.height, 24);
    expect(track.contains(tester.getCenter(find.text('100'))), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _host(const BarBattery(level: 80, isPowerSaver: true, isCharging: false)),
    );
    final saverFillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(saverFillBox.color, const Color(0xFFF2E70D));
    final clipper = tester.widget<ClipPath>(find.byType(ClipPath)).clipper!;
    final fill = clipper.getClip(const Size(48, 24));
    expect(fill.contains(const Offset(1, 12)), isTrue);
    expect(fill.contains(const Offset(38, 12)), isTrue);
    expect(fill.contains(const Offset(39, 12)), isFalse);
    expect(fill.contains(const Offset(36, 1)), isFalse);
    expect(fill.contains(const Offset(34, 1)), isTrue);

    await tester.pumpWidget(
      _host(
        BarBattery(
          isPowerSaver: true,
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 20,
            state: 'Charging',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.bolt_rounded), findsNWidgets(2));
    expect(find.text('20'), findsNWidgets(2));
    final fillBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ClipPath),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(fillBox.color, const Color(0xFFC2230A));

    await tester.pumpWidget(
      _host(
        BarBattery(
          battery: const BatterySnapshot(
            name: 'BAT0',
            percent: 0,
            state: 'Not charging',
          ),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    expect(find.byType(ClipPath), findsNothing);

    await tester.pumpWidget(_host(const BarBattery()));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(
      _host(
        const BarBattery(
          battery: BatterySnapshot(name: 'BAT0', state: 'Unknown'),
        ),
      ),
    );
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
