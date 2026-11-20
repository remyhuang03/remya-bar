import 'dart:io';

/// Launches `remya_screen_capture` detached with optional CLI [arguments].
Future<void> openRemyaScreenCapture({
  File? debugExecutable,
  List<String> arguments = const [],
}) => _openApp('remya_screen_capture', arguments, debugExecutable);

Future<void> openRemyaClipboard() =>
    _openApp('remya_launcher', const ['--clipboard']);

Future<void> _openApp(
  String name,
  List<String> arguments, [
  File? debugExecutable,
]) async {
  final executable = _resolveExecutable(name, debugExecutable);
  await Process.start(executable, arguments, mode: .detached);
}

String _resolveExecutable(String name, File? debugExecutable) {
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
    final bundled = File('$dataHome/remya/$name/$name');
    if (bundled.existsSync()) return bundled.path;
  }
  if (home != null && home.startsWith('/')) {
    final command = File('$home/.local/bin/$name');
    if (command.existsSync()) return command.path;
  }
  return name;
}
