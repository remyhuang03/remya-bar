import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'app.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/settings/bar_theme_controller.dart';
import 'features/popups/popup_app.dart';
import 'features/system/system_backend.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--remya-popup')) {
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
  final system = SystemBackend()..start();
  final hyprland = HyprlandBackend()..start();
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
          '${Directory(root).parent.path}/remya_settings/build/linux/x64/debug/bundle/remya_settings',
        );
  runApp(
    RemyaBarApp(
      preferences: preferences,
      hyprland: hyprland,
      system: system,
      onOpenSettings: () => openRemyaSettings(debugExecutable: debugSettings),
      onOpenPowerSettings: () =>
          openRemyaSettings(debugExecutable: debugSettings, page: 'power'),
    ),
  );
}
