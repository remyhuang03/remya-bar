import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

/// The absolute repository root supplied by the debug runner, else null.
Future<String?> barRepositoryRoot() async => kDebugMode
    ? await const MethodChannel('top.remya.paths')
          .invokeMethod<String>('repositoryDirectory')
    : null;

/// Debug follows the resolved theme file; release follows the Core service.
SettingsThemeController barThemeController(String? root) => kDebugMode
    ? SettingsThemeController(
        () => resolveBarTheme(
          isDebug: true,
          repositoryDirectory: root == null ? null : Directory(root).absolute,
        ),
      )
    : SettingsThemeController.service();

File resolveBarTheme({required bool isDebug, Directory? repositoryDirectory}) {
  if (isDebug && repositoryDirectory != null) {
    final local = File('${repositoryDirectory.path}/config/config.local.toml');
    if (local.existsSync()) return local;
    final settings = settingsConfigFile(
      isDebug: true,
      repositoryDirectory: Directory(
        '${repositoryDirectory.parent.path}/remya-core',
      ),
    );
    if (settings.existsSync()) return settings;
  }
  return settingsConfigFile(isDebug: false);
}
