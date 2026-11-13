import 'dart:io';

DateTime? _checked;
bool _installed = false;

/// Tests set this to make Settings buttons independent of the host.
bool? debugRemyaSettingsInstalled;

/// Whether Remya Settings' desktop entry exists in the XDG data roots, so
/// buttons opening system Settings pages can be hidden when it is missing.
/// Relative XDG values are ignored.
// shortcut: cached for five seconds instead of watching the data dirs; switch
// to a file monitor if installs must be reflected instantly.
bool remyaSettingsInstalled({Map<String, String>? environment}) {
  if (environment == null && debugRemyaSettingsInstalled != null) {
    return debugRemyaSettingsInstalled!;
  }
  final now = DateTime.now();
  if (environment == null &&
      _checked != null &&
      now.difference(_checked!) < const Duration(seconds: 5)) {
    return _installed;
  }
  final env = environment ?? Platform.environment;
  final home = env['XDG_DATA_HOME'];
  final roots = [
    if (home != null && home.startsWith('/'))
      home
    else if (env['HOME'] case final user? when user.startsWith('/'))
      '$user/.local/share',
    ...(env['XDG_DATA_DIRS']?.isNotEmpty == true
            ? env['XDG_DATA_DIRS']!
            : '/usr/local/share:/usr/share')
        .split(':')
        .where((root) => root.startsWith('/')),
  ];
  final installed = roots.any(
    (root) =>
        File('$root/applications/top.remya.settings.desktop').existsSync(),
  );
  if (environment == null) {
    _checked = now;
    _installed = installed;
  }
  return installed;
}
