import 'dart:io';

/// Launches `remya_screen_capture` detached with optional CLI [arguments].
Future<void> openRemyaScreenCapture({
  File? debugExecutable,
  List<String> arguments = const [],
}) async {
  final executable = _resolveExecutable(debugExecutable);
  await Process.start(executable, arguments, mode: .detached);
}

String _resolveExecutable(File? debugExecutable) {
  if (debugExecutable != null && debugExecutable.existsSync()) {
    return debugExecutable.path;
  }
  final home = Platform.environment['HOME'];
  final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
  final dataHome = xdgDataHome != null && xdgDataHome.startsWith('/')
      ? xdgDataHome
      : home != null && home.startsWith('/')
      ? '$home/.local/share'
      : null;
  if (dataHome != null) {
    final bundled = File(
      '$dataHome/remya/remya_screen_capture/remya_screen_capture',
    );
    if (bundled.existsSync()) return bundled.path;
  }
  if (home != null && home.startsWith('/')) {
    final command = File('$home/.local/bin/remya_screen_capture');
    if (command.existsSync()) return command.path;
  }
  return 'remya_screen_capture';
}
