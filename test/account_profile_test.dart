import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/account/account_profile_controller.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

class _Client extends SettingsClient {
  Map<String, dynamic> value = {
    'api_version': 1,
    'username': 'remy',
    'avatar_path': '/tmp/avatar.png',
    'avatar_revision': '1',
    'error': null,
  };
  bool closed = false;
  final updates = StreamController<SettingsChange>.broadcast();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    expect(method, 'Get');
    expect(arguments, [accountInformationKey]);
    return value;
  }

  @override
  Stream<SettingsChange> get changes => updates.stream;

  @override
  Future<void> close() async {
    closed = true;
    await updates.close();
    await super.close();
  }
}

void main() {
  test(
    'profile refresh retains valid data on invalid or failed readback',
    () async {
      final client = _Client();
      final profile = AccountProfileController(client: client);
      await profile.refresh();
      expect(profile.data['username'], 'remy');
      expect(profile.data['avatar_revision'], '1');
      client.value = {...client.value, 'avatar_path': 'relative.png'};
      await profile.refresh();
      expect(profile.data['avatar_path'], '/tmp/avatar.png');
      client.value = {
        ...client.value,
        'avatar_path': null,
        'error': 'unreadable',
      };
      await profile.refresh();
      expect(profile.data['avatar_path'], '/tmp/avatar.png');
      client.value = {
        ...client.value,
        'avatar_path': null,
        'avatar_revision': null,
        'error': null,
      };
      await profile.refresh();
      expect(profile.data['avatar_path'], isNull);
      profile.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(client.closed, isTrue);
    },
  );

  test('Settings account change refreshes the profile', () async {
    final client = _Client();
    final profile = AccountProfileController(client: client)..start();
    await Future<void>.delayed(Duration.zero);
    client.value = {...client.value, 'avatar_revision': '2'};
    client.updates.add((topic: accountInformationKey, value: client.value));
    await Future<void>.delayed(Duration.zero);
    expect(profile.data['avatar_revision'], '2');
    profile.dispose();
  });
}
