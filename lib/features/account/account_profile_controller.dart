import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

/// Observes Core’s shared profile for the Bar sidebar.
class AccountProfileController extends ChangeNotifier {
  AccountProfileController({SettingsClient? client})
    : _client = client ?? SettingsClient();

  final SettingsClient _client;
  StreamSubscription<SettingsChange>? _changes;
  Timer? _timer;
  bool _loading = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  Map<String, Object?> data = const {};

  void start() {
    if (_disposed || _timer != null) return;
    _changes = _client.changes.listen((change) {
      if (change.topic == accountInformationKey) unawaited(refresh());
    }, onError: (Object error) => debugPrint('Account profile: $error'));
    unawaited(refresh());
    // Periodic readback catches changes made outside Core.
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_loading) {
      _refreshQueued = true;
      return;
    }
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
        throw const FormatException("Invalid Remy'a account profile");
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
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refresh());
      }
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
