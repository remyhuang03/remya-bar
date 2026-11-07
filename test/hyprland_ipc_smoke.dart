import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:remya_bar/src/rust/hyprland_bridge/api.dart';
import 'package:remya_bar/src/rust/hyprland_bridge/frb_generated.dart';

// Requires a running compositor; create/open a window to trigger an event.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  await HyprlandRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${root.path}/target/debug/libremya_bar_hyprland.so',
    ),
  );
  try {
    final monitors =
        jsonDecode(await hyprlandRequest(command: 'j/monitors')) as List;
    if (monitors.isEmpty) throw StateError('No active outputs');
    final expected = monitors.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final row = (a['y'] as int).compareTo(b['y'] as int);
        if (row != 0) return row;
        final column = (a['x'] as int).compareTo(b['x'] as int);
        return column != 0
            ? column
            : (a['name'] as String).compareTo(b['name'] as String);
      });
    final snapshot = await hyprlandSnapshot();
    if (snapshot.monitors.length != expected.length) {
      throw StateError('Output count changed during the snapshot');
    }
    for (var i = 0; i < expected.length; i++) {
      final monitor = snapshot.monitors[i];
      if (monitor.name != expected[i]['name'] ||
          monitor.outputNumber != i + 1) {
        throw StateError('Output numbering disagrees with compositor geometry');
      }
    }
    stdout.writeln(
      'PASS: ${snapshot.monitors.map((m) => '${m.outputNumber} ${m.name}').join(', ')}',
    );
    final event = await subscribeHyprland()
        .firstWhere((update) => update.kind == 'event')
        .timeout(const Duration(seconds: 20));
    if (event.name.isEmpty) throw StateError('Empty event name');
    stdout.writeln(
      'PASS: Rust socket1 returned ${monitors.length} monitors; socket2 delivered ${event.name}',
    );
  } finally {
    HyprlandRustLib.dispose();
  }
}
