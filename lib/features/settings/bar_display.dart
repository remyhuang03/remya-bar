import 'package:remya_client/remya_client.dart';

const displayGammaSettingId = 'display-gamma';

/// Core exposes these system operations through Get/Set, without typed helpers.
class BarDisplay {
  BarDisplay(this.client);
  final SettingsClient client;

  Future<int?> setBrightness(String output, int percent) async =>
      (await client.call('Set', [
            'display-brightness:$output',
            '$percent',
          ]))['percent']
          as int?;
  Future<int> readGamma() async =>
      (await client.call('Get', [displayGammaSettingId]))['gamma'] as int;
  Future<int> setGamma(int percent) async =>
      (await client.call('Set', [displayGammaSettingId, '$percent']))['gamma']
          as int;
}
