import 'package:remya_client/remya_client.dart';

const displayGammaTopic = 'display-gamma';

String displayGammaSettingId(String output) => '$displayGammaTopic:$output';

enum BrightnessMode { hardware, hardwareOnly, software, softwareWithFloor }

/// Core exposes these system operations through Get/Set, without typed helpers.
class BarDisplay {
  BarDisplay(this.client);
  final SettingsClient client;

  Future<int?> _setBrightness(String output, int percent) async =>
      (await client.call('Set', [
            'display-brightness:$output',
            '$percent',
          ]))['percent']
          as int?;
  static int? gammaFor(String output, Map<String, Object?> payload) {
    final gamma = payload['gamma'];
    return payload['output'] == output &&
            payload['available'] == true &&
            gamma is int &&
            gamma >= 10 &&
            gamma <= 100
        ? gamma
        : null;
  }

  Future<int?> readGamma(String output) async => gammaFor(
    output,
    await client.call('Get', [displayGammaSettingId(output)]),
  );

  Future<int> _setGamma(String output, int percent) async {
    final payload = await client.call('Set', [
      displayGammaSettingId(output),
      '$percent',
    ]);
    final actual = gammaFor(output, payload);
    if (actual == null) {
      throw StateError('Software dimming unavailable on $output');
    }
    return actual;
  }

  Future<void> setLevel(
    String output, {
    required int? hardware,
    required int? gamma,
    required int target,
    required BrightnessMode mode,
    required bool Function() isCurrent,
    required void Function(int? hardware, int? gamma) onReadback,
    int? previousHardware,
  }) async {
    if (!isCurrent()) return;

    Future<void> writeHardware(int level) async {
      final actual = await _setBrightness(output, level);
      if (!isCurrent()) return;
      if (actual == null) {
        throw StateError('Missing hardware brightness readback');
      }
      hardware = actual;
      onReadback(hardware, gamma);
      if (level == 0 && actual != 0) {
        throw StateError('Display did not reach its minimum backlight');
      }
    }

    Future<void> writeGamma(int level) async {
      final actual = await _setGamma(output, level);
      if (!isCurrent()) return;
      gamma = actual;
      onReadback(hardware, gamma);
      if (actual != level) throw StateError('Display did not apply gamma');
    }

    if (mode == .hardware || mode == .hardwareOnly) {
      if (mode == .hardware && gamma != null && gamma != 100) {
        await writeGamma(100);
      }
      if (isCurrent() && hardware != target) await writeHardware(target);
      return;
    }

    final before = previousHardware ?? hardware;
    if (mode == .softwareWithFloor && hardware != null && hardware != 0) {
      await writeHardware(0);
    }
    if (!isCurrent() || gamma == target) return;
    try {
      await writeGamma(target);
    } catch (error) {
      if (isCurrent() && hardware == 0 && before != null && before > 0) {
        try {
          await writeHardware(before);
        } catch (restoreError) {
          throw StateError(
            '$error. Backlight restoration failed: $restoreError',
          );
        }
      }
      rethrow;
    }
  }
}
