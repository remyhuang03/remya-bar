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
