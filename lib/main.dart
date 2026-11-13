import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

import 'app.dart';
import 'features/account/account_profile_controller.dart';
import 'features/ai_usage/ai_usage_backend.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/notifications/notification_backend.dart';
import 'features/osd/osd_controller.dart';
import 'features/settings/bar_theme_controller.dart';
import 'features/popups/popup_app.dart';
import 'features/popups/bar_popup.dart';
import 'features/sidebar/sidebar_screen_capture.dart';
import 'features/system/system_backend.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Unknown providers fall back to initials if the manifest cannot load.
  await loadAiIdentity().catchError(
    (Object error) => debugPrint('AI provider identity unavailable: $error'),
  );
  if (arguments.contains('--remya-popup')) {
    runWidget(const BarPopupHost());
    startAiUsageWorker();
    return;
  }
  final root = await barRepositoryRoot();
  final preferences = barThemeController(root);
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
  final debugScreenCapture = root == null
      ? null
      : File(
          '${Directory(root).parent.path}/remya-screen-capture/build/linux/x64/debug/bundle/remya_screen_capture',
        );
  runApp(
    RemyaBarApp(
      preferences: preferences,
      hyprland: hyprland,
      system: system,
      aiUsage: AiUsageBackend()..start(),
      account: AccountProfileController()..start(),
      notifications: NotificationBackend()..start(),
      osd: OsdController()..start(output: hyprland.output?.name),
      onOpenSettingsPage: (page) =>
          openRemyaSettings(debugExecutable: debugSettings, page: page),
      showTray: true,
      onOpenSettings: () => openRemyaSettings(debugExecutable: debugSettings),
      onOpenPowerSettings: () =>
          openRemyaSettings(debugExecutable: debugSettings, page: 'power'),
      onLaunchScreenCapture: (arguments) => openRemyaScreenCapture(
        debugExecutable: debugScreenCapture,
        arguments: arguments,
      ),
    ),
  );
}
