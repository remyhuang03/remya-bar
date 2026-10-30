import 'dart:async';

import 'package:material_ui/material_ui.dart';

class BarClock extends StatefulWidget {
  const BarClock({super.key});

  @override
  State<BarClock> createState() => _BarClockState();
}

class _BarClockState extends State<BarClock> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _now = DateTime.now();
    // Re-align each tick after clock adjustments instead of accumulating drift.
    _timer = Timer(
      Duration(
        microseconds: 1000000 - _now.microsecond - _now.millisecond * 1000,
      ),
      () => setState(_tick),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _now.toIso8601String().substring(0, 19).replaceFirst('T', '  '),
    maxLines: 1,
    overflow: .ellipsis,
    textAlign: .center,
    style: Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}
