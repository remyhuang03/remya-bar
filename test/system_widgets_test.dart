import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/media/media_preview.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_ui/remya_ui.dart';

Widget _host(Widget child, {double scale = 1}) => BarPopupScope(
  theme: RemyaTheme(),
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: .linear(scale)),
      child: Material(child: child),
    ),
  ),
);

Finder _batteryFill() => find.descendant(
  of: find.byType(ClipRRect),
  matching: find.byType(ClipPath),
);

void main() {
  for (final seek in [true, false]) {
    testWidgets(
      '${seek ? 'seek' : 'volume'} holds a commit until match or timeout',
      (tester) async {
        Widget host(double value) => _mediaSliders((_) {}, value: value);
        Finder slider() =>
            seek ? find.byType(Slider).first : find.byType(Slider).last;
        Slider control() => tester.widget<Slider>(slider());

        await tester.pumpWidget(host(0.2));
        control().onChanged!(0.7);
        control().onChangeEnd!(0.7);
        await tester.pump();
        expect(control().value, 0.7);
        await tester.pumpWidget(host(0.2));
        expect(control().value, 0.7);
        await tester.pumpWidget(host(0.704));
        expect(control().value, closeTo(0.704, 0.0001));
        await tester.pumpWidget(host(0.2));
        expect(control().value, 0.2);
        control().onChanged!(0.8);
        control().onChangeEnd!(0.8);
        await tester.pump(const Duration(milliseconds: 1499));
        expect(control().value, 0.8);
        await tester.pump(const Duration(milliseconds: 1));
        expect(control().value, 0.2);
      },
    );
  }

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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
    );
    expect(saverFillBox.color, const Color(0xFFF2E70D));
    final clipper = tester.widget<ClipPath>(_batteryFill()).clipper!;
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
      find.descendant(of: _batteryFill(), matching: find.byType(ColoredBox)),
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
    expect(_batteryFill(), findsNothing);

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

Widget _mediaSliders(
  ValueChanged<Map<String, Object?>> onAction, {
  double value = 0.2,
}) => _host(
  MediaPreview(
    data: {
      'players': [
        {
          'name': 'test',
          'identity': 'Test player',
          'title': 'Track',
          'status': 'Paused',
          'positionSeconds': value * 100,
          'lengthSeconds': 100,
          'seekToken': ':1.2/track',
        },
      ],
      'output': {'name': 'speaker', 'percent': value * 100},
    },
    onAction: onAction,
  ),
);
