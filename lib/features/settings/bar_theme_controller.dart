import 'dart:io';

import 'package:remya_settings_client/remya_settings_client.dart';

File resolveBarTheme({required bool isDebug, Directory? repositoryDirectory}) {
  if (isDebug && repositoryDirectory != null) {
    final local = settingsConfigFile(
      isDebug: true,
      repositoryDirectory: repositoryDirectory,
    );
    if (local.existsSync()) return local;
    final settings = settingsConfigFile(
      isDebug: true,
      repositoryDirectory: Directory(
        '${repositoryDirectory.parent.path}/remya_settings',
      ),
    );
    if (settings.existsSync()) return settings;
  }
  return settingsConfigFile(isDebug: false);
}
