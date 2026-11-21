import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

import 'app.dart';
import 'bar_view_host.dart';
import 'features/settings/bar_live_pills.dart';
import 'features/account/account_profile_controller.dart';
import 'features/ai_usage/ai_usage_backend.dart';
import 'features/hyprland/hyprland_backend.dart';
import 'features/notifications/notification_backend.dart';
import 'features/notifications/notification_settings.dart';
import 'features/osd/osd_controller.dart';
import 'features/popups/bar_popup.dart';
import 'features/settings/bar_theme_controller.dart';
import 'features/sidebar/sidebar_app_launcher.dart';
import 'features/system/system_backend.dart';
import 'features/tasks/tasks_integration.dart';
import 'features/tray/tray_backend.dart';
import 'features/weather/weather_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await barRepositoryRoot();
  final preferences = barThemeController(root);
  final identity = loadAiIdentity().catchError(
    (Object error) => debugPrint('AI provider identity unavailable: $error'),
  );
  await Future.wait([
    preferences.start(),
    HyprlandBackend.initialize(),
    SystemBackend.initialize(),
  ]);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Bar",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Meteocons',
    ], await rootBundle.loadString('assets/icons/weather/LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Rust backend dependencies',
    ], await rootBundle.loadString('assets/licenses/rust-dependencies.txt'));
  });
  runWidget(_BarApplication(preferences: preferences, repositoryRoot: root));
  unawaited(identity);
}

class _BarApplication extends StatefulWidget {
  const _BarApplication({required this.preferences, this.repositoryRoot});

  final SettingsThemeController preferences;
  final String? repositoryRoot;

  @override
  State<_BarApplication> createState() => _BarApplicationState();
}

class _BarApplicationState extends State<_BarApplication> {
  final _hyprland = HyprlandStore();
  final _system = SystemBackend();
  final _aiUsage = AiUsageBackend();
  final _account = AccountProfileController();
  final _notifications = NotificationBackend();
  final _notificationSettings = NotificationSettings();
  final _tray = TrayBackend();
  final _osdSettings = SettingsClient();
  late final _debugSettings = _debugExecutable(
    'remya-settings',
    'remya_settings',
  );
  late final _debugScreenCapture = _debugExecutable(
    'remya-screen-capture',
    'remya_screen_capture',
  );

  File? _debugExecutable(String repository, String executable) {
    final root = widget.repositoryRoot;
    return root == null
        ? null
        : File(
            '${Directory(root).parent.path}/$repository/build/linux/x64/debug/bundle/$executable',
          );
  }

  @override
  void initState() {
    super.initState();
    _hyprland.start();
    _system.start();
    _aiUsage.start();
    _account.start();
    _notifications.start();
    _notificationSettings.start();
    unawaited(TasksIntegration.shared.start());
  }

  @override
  void dispose() {
    TasksIntegration.shared.dispose();
    unawaited(_notificationSettings.close());
    unawaited(_osdSettings.close());
    _notifications.dispose();
    _tray.dispose();
    _account.dispose();
    _aiUsage.dispose();
    _system.dispose();
    _hyprland.dispose();
    widget.preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BarLiveServices(
    theme: widget.preferences,
    hyprland: _hyprland,
    system: _system,
    weather: WeatherController.instance,
    notifications: _notifications,
    aiUsage: _aiUsage,
    tray: _tray,
    child: BarViewHost(
      preferences: widget.preferences,
      buildBar: (viewId) => _BarOutput(viewId: viewId, app: this),
    ),
  );
}

class _BarOutput extends StatefulWidget {
  const _BarOutput({required this.viewId, required this.app});

  final int viewId;
  final _BarApplicationState app;

  @override
  State<_BarOutput> createState() => _BarOutputState();
}

class _BarOutputState extends State<_BarOutput> {
  late final _popup = BarPopup.forView(widget.viewId);
  late final _window = MethodChannel(
    'top.remya.bar/bar/${widget.viewId}/window',
  );
  late final _hyprland = HyprlandBackend(store: widget.app._hyprland);
  late final _osd = OsdController(settings: widget.app._osdSettings)..start();

  @override
  void initState() {
    super.initState();
    unawaited(
      _popup.syncKeyboardVisibility().catchError((Object error) {
        if (mounted) debugPrint('Bar keyboard visibility: $error');
      }),
    );
  }

  @override
  void dispose() {
    _osd.dispose();
    _hyprland.dispose();
    _popup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return RemyaBarApp(
      weather: WeatherController.instance,
      preferences: app.widget.preferences,
      popup: _popup,
      window: _window,
      hyprland: _hyprland,
      system: app._system,
      aiUsage: app._aiUsage,
      account: app._account,
      notifications: app._notifications,
      osd: _osd,
      onOpenSettingsPage: (page) =>
          openRemyaSettings(debugExecutable: app._debugSettings, page: page),
      tray: app._tray,
      onOpenSettings: () =>
          openRemyaSettings(debugExecutable: app._debugSettings),
      onOpenPowerSettings: () =>
          openRemyaSettings(debugExecutable: app._debugSettings, page: 'power'),
      onLaunchScreenCapture: (arguments) => openRemyaScreenCapture(
        debugExecutable: app._debugScreenCapture,
        arguments: arguments,
      ),
    );
  }
}
