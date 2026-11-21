import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/weather/weather_controller.dart';

void main() {
  test('nextWeatherDeadline picks earliest of refresh, staleness, expiry, and cooldowns', () {
    expect(
      nextWeatherDeadline(
        automatic: false,
        background: false,
        intervalMinutes: 15,
        cacheAge: null,
        hasSnapshot: false,
        hasError: false,
        waitingFailure: false,
        retryAfterRequired: false,
        sinceFailure: Duration.zero,
        retryDelay: Duration.zero,
        manualRunning: false,
        sinceManual: Duration.zero,
      ),
      isNull,
    );

    // Automatic refresh due in 10 minutes beats 30 min staleness.
    expect(
      nextWeatherDeadline(
        automatic: true,
        background: true,
        intervalMinutes: 15,
        cacheAge: const Duration(minutes: 5),
        hasSnapshot: true,
        hasError: false,
        waitingFailure: false,
        retryAfterRequired: false,
        sinceFailure: Duration.zero,
        retryDelay: Duration.zero,
        manualRunning: false,
        sinceManual: Duration.zero,
      ),
      const Duration(minutes: 10),
    );

    // Manual cooldown (20s left) beats 25 min staleness when automatic is off.
    expect(
      nextWeatherDeadline(
        automatic: false,
        background: false,
        intervalMinutes: 15,
        cacheAge: const Duration(minutes: 5),
        hasSnapshot: true,
        hasError: false,
        waitingFailure: false,
        retryAfterRequired: false,
        sinceFailure: Duration.zero,
        retryDelay: Duration.zero,
        manualRunning: true,
        sinceManual: const Duration(seconds: 40),
      ),
      const Duration(seconds: 20),
    );

    // Past staleness (45 min) with no cooldown schedules 24h expiry.
    expect(
      nextWeatherDeadline(
        automatic: false,
        background: false,
        intervalMinutes: 15,
        cacheAge: const Duration(minutes: 45),
        hasSnapshot: true,
        hasError: false,
        waitingFailure: false,
        retryAfterRequired: false,
        sinceFailure: Duration.zero,
        retryDelay: Duration.zero,
        manualRunning: false,
        sinceManual: Duration.zero,
      ),
      const Duration(hours: 23, minutes: 15),
    );
  });
}
