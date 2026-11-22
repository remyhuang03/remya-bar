import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import '../tasks/tasks_settings.dart';
import '../tasks/tasks_store.dart';
import 'bar_settings_controller.dart';
import 'bar_settings_tiles.dart';

/// Connects the shared Remya account from Bar settings.
class BarGoogleAccount extends StatefulWidget {
  const BarGoogleAccount({
    super.key,
    required this.client,
    required this.pickAvatar,
  });

  final SettingsClient client;
  final Future<String?> Function() pickAvatar;

  @override
  State<BarGoogleAccount> createState() => _BarGoogleAccountState();
}

class _BarGoogleAccountState extends State<BarGoogleAccount> {
  late final StreamSubscription<SettingsChange> _changes;
  late final StreamSubscription<bool> _serviceChanges;
  GoogleAccountStatus? _status;
  String? _error;
  bool _busy = false;
  bool _refreshNeeded = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.client.changes.listen((change) {
      if (change.topic == googleAccountTopic) unawaited(_refresh());
    }, onError: (Object _) {});
    _serviceChanges = widget.client.serviceAvailableChanges.listen((available) {
      if (available) unawaited(_refresh());
    }, onError: (Object _) {});
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    unawaited(_serviceChanges.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) {
      _refreshNeeded = true;
      return;
    }
    await _run(widget.client.googleAccountStatus);
  }

  Future<void> _run(Future<GoogleAccountStatus> Function() request) async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final status = await request();
      if (!mounted) return;
      _status = status;
      _error = null;
    } catch (error) {
      if (!mounted) return;
      _error = barSettingsError(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshNeeded) {
          _refreshNeeded = false;
          unawaited(_refresh());
        }
      }
    }
  }

  Future<void> _disconnect() async {
    if (await confirmGoogleDisconnect(context, TasksStore.shared) && mounted) {
      await _run(widget.client.disconnectGoogleAccount);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final result = await Process.run('xdg-open', [
        'https://apps.remya.top/privacy',
      ]);
      if (result.exitCode == 0) return;
    } on ProcessException {
      // The desktop opener may be unavailable.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the privacy policy.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final pending = status?.pending ?? false;
    final email = status?.email;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (_error case final error?)
          SettingsErrorCard(message: error, onRetry: _busy ? null : _refresh)
        else if (status?.error case final error?)
          SettingsErrorCard(message: error, actionLabel: null),
        SettingsGroup(
          title: 'Google account',
          trailing: TextButton.icon(
            onPressed: _openPrivacyPolicy,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Privacy policy'),
          ),
          children: [
            settingTile(
              email ?? 'Connect a Google account',
              leading: Image.asset(
                'assets/icons/google.png',
                width: 20,
                height: 20,
                excludeFromSemantics: true,
              ),
              detail: switch (status) {
                null => _busy ? 'Checking connection…' : 'Status unavailable',
                _ when pending => 'Continue in your browser',
                _ when !status.configured =>
                  'Google sign-in is unavailable on this installation',
                _ => null,
              },
              control: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pending)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.client.cancelGoogleAuthorization),
                      child: const Text('Cancel sign-in'),
                    ),
                  if (status?.configured == true && !pending && email == null)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.client.connectGoogleAccount),
                      child: const Text('Connect'),
                    ),
                  if (email != null && !pending)
                    OutlinedButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SettingsSectionTitle('Profile picture'),
        SettingsSurface(
          child: settingSwitch(
            'Sync with Google account',
            email == null
                ? 'Connect a Google account to sync your picture'
                : null,
            status?.avatarSync ?? false,
            _busy || pending || email == null
                ? null
                : (enabled) =>
                      _run(() => widget.client.setGoogleAvatarSync(enabled)),
          ),
        ),
        const SizedBox(height: 4),
        RemyaAvatarEditor(client: widget.client, pickImage: widget.pickAvatar),
      ],
    );
  }
}
