import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'app.dart';
import 'features/account/account_profile_controller.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/notifications/notification_backend.dart';
import 'features/settings/bar_theme_controller.dart';
import 'features/popups/popup_app.dart';
import 'features/popups/bar_popup.dart';
import 'features/system/system_backend.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final popup = arguments.contains('--remya-popup');
  if (Platform.environment['REMYA_BAR_PERF'] == '1') _recordFrames(popup);
  if (popup) {
    runApp(const BarPopupApp());
    return;
  }
  final root = kDebugMode
      ? await const MethodChannel('top.remya.paths')
            .invokeMethod<String>('repositoryDirectory')
      : null;
  final preferences = kDebugMode
      ? SettingsThemeController(
          () => resolveBarTheme(
            isDebug: kDebugMode,
            repositoryDirectory: root == null ? null : Directory(root).absolute,
          ),
        )
      : SettingsThemeController.service();
  await preferences.start();
  await HyprlandBackend.initialize();
  await SystemBackend.initialize();
  final output = await const MethodChannel('top.remya.bar/window')
      .invokeMapMethod<String, int>('output');
  BarPopup.keyboardOpen.value =
      await BarPopup.channel.invokeMethod<bool>('keyboardVisible') ?? false;
  final hyprland = HyprlandBackend(outputX: output?['x'], outputY: output?['y'])
    ..start();
  final system = SystemBackend()..start();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Bar",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Rust backend dependencies',
    ], await rootBundle.loadString('assets/licenses/rust-dependencies.txt'));
  });
  final debugSettings = root == null
      ? null
      : File(
          '${Directory(root).parent.path}/remya-settings/build/linux/x64/debug/bundle/remya_settings',
        );
  runApp(
    RemyaBarApp(
      preferences: preferences,
      hyprland: hyprland,
      system: system,
      account: AccountProfileController()..start(),
      notifications: NotificationBackend()..start(),
      onOpenSettingsPage: (page) =>
          openRemyaSettings(debugExecutable: debugSettings, page: page),
      showTray: true,
      onOpenSettings: () => openRemyaSettings(debugExecutable: debugSettings),
      onOpenPowerSettings: () =>
          openRemyaSettings(debugExecutable: debugSettings, page: 'power'),
    ),
  );
}

void _recordFrames(bool popup) {
  final engine = PlatformDispatcher.instance.engineId;
  final samples = <FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback(samples.addAll);
  Timer.periodic(const Duration(seconds: 5), (_) {
    int p95(Duration Function(FrameTiming) duration) {
      if (samples.isEmpty) return 0;
      final values = samples.map((f) => duration(f).inMicroseconds).toList()
        ..sort();
      return values[(values.length * .95).ceil() - 1];
    }

    debugPrintSynchronously(
      'BAR_PERF ${jsonEncode({'engine': engine, 'popup': popup, 'end_ms': DateTime.now().millisecondsSinceEpoch, 'frames': samples.length, 'build_p95_us': p95((f) => f.buildDuration), 'raster_p95_us': p95((f) => f.rasterDuration), 'total_p95_us': p95((f) => f.totalSpan)})}',
    );
    samples.clear();
  });
}
