import 'ai_usage_data.dart';

/// Coordinates periodic and manual requests for the shared usage sample.
class AiUsagePoll {
  AiUsagePoll(this._poll, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<bool> Function(bool force) _poll;
  final DateTime Function() _now;
  Future<void>? _normal;
  Future<void>? _forced;
  DateTime? _nextPoll;
  DateTime? _nextForce;
  int _failures = 0;
  int _generation = 0;

  DateTime? get nextPoll => _nextPoll;

  Duration nextDelay() {
    final next = _nextPoll;
    if (next == null) return Duration.zero;
    final delay = next.difference(_now());
    return delay > Duration.zero ? delay : Duration.zero;
  }

  void invalidate() {
    _generation++;
    _nextPoll = null;
    _failures = 0;
  }

  Future<void> read(bool force) async {
    if (force) {
      await (_forced ??= _force().whenComplete(() => _forced = null));
      return;
    }
    if ((_forced ?? _normal) case final pending?) {
      await pending;
      return;
    }
    if (_nextPoll case final next? when _now().isBefore(next)) return;
    await (_normal ??= _run(false).whenComplete(() => _normal = null));
  }

  Future<void> _force() async {
    await _normal;
    if (_nextForce case final earliest?) {
      final wait = earliest.difference(_now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _nextForce = _now().add(const Duration(seconds: 2));
    await _run(true);
  }

  Future<void> _run(bool force) async {
    final generation = _generation;
    var succeeded = false;
    try {
      succeeded = await _poll(force);
    } catch (_) {
      // Keep serving the previous sample until the next attempt.
    }
    if (generation != _generation) return;
    final Duration delay;
    if (succeeded) {
      _failures = 0;
      delay = aiRefreshInterval;
    } else {
      delay = Duration(seconds: 5 << _failures);
      if (_failures < 4) _failures++;
    }
    _nextPoll = _now().add(delay);
  }
}
