import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';

void main() {
  testWidgets('shared clock publishes at each consumer cadence', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 18, 12, 34, 58, 500);
    final source = BarClockSource(now: () => now);
    final minutes = <DateTime>[];
    final seconds = <DateTime>[];
    final onMinute = minutes.add;
    final onSecond = seconds.add;

    Future<void> advance(int millis) async {
      final duration = Duration(milliseconds: millis);
      now = now.add(duration);
      await tester.pump(duration);
    }

    expect(source.attach(onMinute, seconds: false), now);
    source.attach(onSecond, seconds: true);
    await advance(500);
    expect(seconds, [now]);
    expect(minutes, isEmpty);
    await advance(1000);
    expect(seconds.length, 2);
    expect(minutes, [now]);

    source.detach(onSecond);
    await advance(59000);
    expect(seconds.length, 2);
    expect(minutes.length, 1);
    await advance(1000);
    expect(minutes.length, 2);
    source.detach(onMinute);
    await advance(60000);
    expect(minutes.length, 2);
  });
}
