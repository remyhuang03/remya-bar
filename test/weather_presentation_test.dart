import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/remya_ui.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/weather/bar_weather.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_bar/features/weather/weather_backend.dart';
import 'package:remya_bar/features/weather/weather_card.dart';
import 'package:remya_bar/features/weather/weather_controller.dart';
import 'package:remya_bar/features/weather/weather_presentation.dart';

void main() {
  test(
    'uses location timezone through DST and formats units independently',
    () {
      final format = WeatherFormat.forLocale(const Locale('en', 'US'), {
        ...weatherDefaults,
        'wind': 'kn',
        'precipitation': 'in',
      }, use24Hour: true);
      int at(String iso) => DateTime.parse(iso).millisecondsSinceEpoch ~/ 1000;
      expect(
        format.time(at('2026-03-08T06:59:00Z'), 'America/New_York'),
        '01:59',
      );
      expect(
        format.time(at('2026-03-08T07:00:00Z'), 'America/New_York'),
        '03:00',
      );
      expect(format.weekday('2026-03-08'), 'Sun');
      expect(format.temperature(40), '104°');
      expect(format.temperature(null), '—');
      expect(format.temperature(-40, withUnit: true), '-40 °F');
      expect(format.temperature(-17.8, precise: true), '0.0°');
      expect(format.wind(18.52, 45), '10 kn NE');
      expect(format.probability(0), '0%');
      expect(format.precipitation(25.4), '1.00 in');
      expect(weatherCondition(.storm, 97), 'Heavy thunderstorm');
      expect(weatherCondition(null, 255), 'Weather condition unavailable');
      expect(weatherSeed(null), isNull);
    },
  );

  testWidgets('the weather pill keeps a fixed Inter Regular temperature box', (
    tester,
  ) async {
    final weather = _CardWeather();
    await tester.pumpWidget(
      MaterialApp(
        home: BarPopupScope(
          theme: const RemyaTheme(),
          child: Material(
            child: Center(child: BarWeather(weather: weather)),
          ),
        ),
      ),
    );
    Finder temperature(String token) => find.text(token);
    final original = temperature('40°');
    final box = find
        .ancestor(of: original, matching: find.byType(SizedBox))
        .first;
    final originalWidth = tester.getSize(box).width;
    final text = tester.widget<Text>(original);
    expect(text.style?.fontFamily, 'Inter');
    expect(text.style?.fontWeight, FontWeight.w400);

    weather.changePill('f', true);
    await tester.pump();
    final fahrenheit = find
        .ancestor(of: temperature('104 °F'), matching: find.byType(SizedBox))
        .first;
    expect(tester.getSize(fahrenheit).width, originalWidth);
  });

  testWidgets(
    'hourly and daily forecasts fit large text and retain cache status',
    (tester) async {
      final weather = _CardWeather();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Material(
              child: Center(
                child: SizedBox(
                  width: 372,
                  height: 460,
                  child: SingleChildScrollView(
                    child: WeatherCard(controller: weather, onSettings: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Couldn’t refresh · Showing saved weather\nLast retrieved 42 min ago',
        ),
        findsOneWidget,
      );
      expect(find.text('Heavy thunderstorm'), findsOneWidget);
      await tester.ensureVisible(find.text('7 days'));
      await tester.tap(find.text('7 days'));
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(weather.demand, 0);
    },
  );
}

class _CardWeather extends ChangeNotifier implements WeatherController {
  int demand = 0;
  String _temperature = 'c';
  bool _showUnit = false;
  void changePill(String temperature, bool showUnit) {
    _temperature = temperature;
    _showUnit = showUnit;
    notifyListeners();
  }

  @override
  bool get enabled => true;
  @override
  void showForecast() => demand++;
  @override
  void hideForecast() => demand--;
  @override
  bool get canRefresh => true;
  @override
  bool get refreshing => false;
  @override
  bool get rateLimited => false;
  @override
  bool get stale => true;
  @override
  Duration get age => const Duration(minutes: 42);
  @override
  Map<String, Object> get settings => {
    ...weatherDefaults,
    'temperature': _temperature,
    'show-unit': _showUnit,
  };
  @override
  WeatherLocation get location => const WeatherLocation(
    name: 'Greater Taipei Metropolitan Area',
    latitude: 25,
    longitude: 121.5,
  );
  @override
  WeatherResult get result =>
      WeatherResult(status: .stale, snapshot: snapshot, error: 'Offline');
  @override
  WeatherSnapshot get snapshot {
    final now = DateTime.now().toUtc();
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    return WeatherSnapshot(
      fetchedAt: timestamp - 2520,
      timezone: 'Asia/Taipei',
      current: WeatherCurrent(
        validAt: timestamp,
        temperatureC: 40,
        condition: .storm,
        weatherCode: 97,
        precipitationProbability: 0,
      ),
      hourly: [WeatherHour(validAt: timestamp + 3600, temperatureC: 38)],
      daily: [
        WeatherDay(
          date: now
              .add(const Duration(hours: 8))
              .toIso8601String()
              .split('T')
              .first,
          lowC: 32,
          highC: 41,
          condition: .storm,
          weatherCode: 97,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
