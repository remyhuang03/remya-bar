import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

/// Settings owns identity and avatar paths; the bar only observes its public API.
class AccountProfileController extends ChangeNotifier {
  AccountProfileController({SettingsClient? client})
    : _client = client ?? SettingsClient();

  final SettingsClient _client;
  StreamSubscription<SettingsChange>? _changes;
  Timer? _timer;
  bool _loading = false;
  bool _disposed = false;
  Map<String, Object?> data = const {};

  void start() {
    if (_disposed || _timer != null) return;
    _changes = _client.changes.listen((change) {
      if (change.topic == accountInformationKey) unawaited(refresh());
    }, onError: (Object error) => debugPrint('Account profile: $error'));
    unawaited(refresh());
    // Only edits made outside Settings (another accounts tool) lack a signal.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _loading) return;
    _loading = true;
    try {
      final next = await _client.readAccountInformation();
      final username = next['username'];
      final path = next['avatar_path'];
      final revision = next['avatar_revision'];
      if (next['error'] != null ||
          next['api_version'] != 1 ||
          username is! String ||
          username.isEmpty ||
          (path != null && (path is! String || !path.startsWith('/'))) ||
          (revision != null && revision is! String)) {
        throw const FormatException('Invalid Settings account profile');
      }
      if (_disposed) return;
      final profile = <String, Object?>{
        'username': username,
        'avatar_path': path,
        'avatar_revision': revision,
      };
      if (!mapEquals(data, profile)) {
        data = profile;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Account profile: $error');
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_client.close());
    super.dispose();
  }
}
