import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../src/rust/hyprland_bridge/api.dart';
import '../../src/rust/hyprland_bridge/frb_generated.dart';

export '../../src/rust/hyprland_bridge/api.dart' show HyprlandUpdate;

class HyprlandBackend extends ChangeNotifier {
  StreamSubscription<HyprlandUpdate>? _subscription;
  HyprlandUpdate? latest;
  bool connected = false;

  static Future<void> initialize() => HyprlandRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_bar_hyprland.so',
    ),
  );

  void start() {
    _subscription = subscribeHyprland().listen(
      (update) {
        if (update.kind == 'heartbeat') return;
        latest = update;
        if (update.kind == 'connected') connected = true;
        if (update.kind == 'disconnected') connected = false;
        if (update.kind != 'event') {
          debugPrint('Hyprland IPC: ${update.kind}');
        }
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        connected = false;
        debugPrint('Hyprland IPC: $error');
        notifyListeners();
      },
    );
  }

  Future<String> request(String command) => hyprlandRequest(command: command);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
