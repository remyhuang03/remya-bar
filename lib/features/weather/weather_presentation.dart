import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest.dart' as zone_data;
import 'package:timezone/timezone.dart' as zone;

import 'weather_backend.dart';

const weatherSource = 'Weather data by Open-Meteo';

// Seeds measured from the opaque pixels of the Meteocons fill assets in Figma.
const _conditions = {
  WeatherCondition.clear: ('clear-day', Color(0xFFF8AF18), 'Clear sky'),
  WeatherCondition.partlyCloudy: (
    'partly-cloudy-day',
    Color(0xFFE7EFFC),
    'Partly cloudy',
  ),
  WeatherCondition.cloudy: ('overcast', Color(0xFF97A4BA), 'Cloudy'),
  WeatherCondition.fog: ('fog', Color(0xFFEBF2FD), 'Fog'),
  WeatherCondition.rain: ('rain', Color(0xFFA7C3F0), 'Rain'),
  WeatherCondition.storm: (
    'thunderstorms-rain',
    Color(0xFF58739A),
    'Thunderstorm',
  ),
  WeatherCondition.snow: ('snow', Color(0xFFD6E8F7), 'Snow'),
  WeatherCondition.clearNight: (
    'clear-night',
    Color(0xFF79BDD7),
    'Clear night',
  ),
  WeatherCondition.partlyCloudyNight: (
    'partly-cloudy-night',
    Color(0xFFCBE2F3),
    'Partly cloudy night',
  ),
};

Color? weatherSeed(WeatherCondition? condition) => _conditions[condition]?.$2;

String weatherCondition(WeatherCondition? condition, int? code) =>
    switch (code) {
      48 => 'Rime fog',
      51 => 'Light drizzle',
      53 => 'Drizzle',
      55 => 'Heavy drizzle',
      56 => 'Light freezing drizzle',
      57 => 'Heavy freezing drizzle',
      61 => 'Light rain',
      65 => 'Heavy rain',
      66 => 'Light freezing rain',
      67 => 'Heavy freezing rain',
      71 => 'Light snow',
      75 => 'Heavy snow',
      77 => 'Snow grains',
      80 => 'Light rain showers',
      81 => 'Rain showers',
      82 => 'Heavy rain showers',
      85 => 'Light snow showers',
      86 => 'Heavy snow showers',
      97 => 'Heavy thunderstorm',
      96 || 99 => 'Thunderstorm with hail',
      _ => _conditions[condition]?.$3 ?? 'Weather condition unavailable',
    };

class WeatherIcon extends StatelessWidget {
  const WeatherIcon(
    this.condition, {
    super.key,
    required this.size,
    this.statusIcon,
    this.animated = false,
  });

  final WeatherCondition? condition;
  final double size;
  final IconData? statusIcon;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final asset = _conditions[condition]?.$1;
    final staticIcon = SvgPicture.asset(
      'assets/icons/weather/${asset ?? 'not-available'}.svg',
      width: size,
      height: size,
    );
    return ExcludeSemantics(
      child: asset == null && statusIcon != null
          ? Icon(statusIcon, size: size * .75)
          : asset != null &&
                animated &&
                !MediaQuery.disableAnimationsOf(context)
          ? Lottie.asset(
              'assets/icons/weather/$asset.json',
              width: size,
              height: size,
              errorBuilder: (context, error, stackTrace) => staticIcon,
            )
          : staticIcon,
    );
  }
}

final _zoneReady = (() {
  zone_data.initializeTimeZones();
  return true;
})();
final _datesReady = initializeDateFormatting();

class WeatherFormat {
  WeatherFormat(BuildContext context, Map<String, Object> settings)
    : this.forLocale(
        View.of(context).platformDispatcher.locale,
        settings,
        use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  WeatherFormat.forLocale(
    Locale locale,
    this.settings, {
    this.use24Hour = false,
  }) : locale = Intl.canonicalizedLocale(locale.toLanguageTag()),
       fahrenheit =
           settings['temperature'] == 'f' ||
           (settings['temperature'] == 'system' &&
               const {
                 'US',
                 'BS',
                 'BZ',
                 'KY',
                 'PW',
                 'FM',
                 'MH',
               }.contains(locale.countryCode));

  final String locale;
  final Map<String, Object> settings;
  final bool use24Hour;
  final bool fahrenheit;

  String get unit => fahrenheit ? '°F' : '°C';
  String get spokenUnit =>
      fahrenheit ? 'degrees Fahrenheit' : 'degrees Celsius';

  String number(num value, {bool precise = false}) => NumberFormat(
    precise ? '0.0' : '0',
    locale,
  ).format(precise ? (value * 10).round() / 10 : value.round());

  String temperature(
    double? celsius, {
    bool withUnit = false,
    bool precise = false,
  }) {
    if (celsius == null) return '—';
    final value = fahrenheit ? celsius * 9 / 5 + 32 : celsius;
    final formatted = number(value, precise: precise);
    return withUnit ? '$formatted $unit' : '$formatted°';
  }

  String probability(double? value) =>
      value == null ? '—' : '${number(value)}%';

  String precipitation(double? mm) {
    if (mm == null) return '—';
    final inches = settings['precipitation'] == 'in';
    final value = inches ? mm / 25.4 : mm;
    return "${NumberFormat(inches ? '0.00' : '0.0', locale).format(value)} ${inches ? 'in' : 'mm'}";
  }

  String wind(double? kmh, double? direction) {
    if (kmh == null) return '—';
    final unit = settings['wind'] as String;
    final multiplier = switch (unit) {
      'm/s' => 1 / 3.6,
      'mph' => 1 / 1.609344,
      'kn' => 1 / 1.852,
      _ => 1.0,
    };
    const compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final bearing = direction == null
        ? ''
        : ' ${compass[(direction / 45).round() % 8]}';
    return '${number(kmh * multiplier)} $unit$bearing';
  }

  DateTime localDateTime(int seconds, String timezone) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    try {
      if (_zoneReady) {
        return zone.TZDateTime.from(utc, zone.getLocation(timezone));
      }
    } on zone.LocationNotFoundException {
      return utc;
    }
    return utc;
  }

  String time(int seconds, String timezone) =>
      _dateFormat(use24Hour ? 'Hm' : 'jm')
          .format(localDateTime(seconds, timezone));

  String forecastHour(int seconds, String timezone) => DateFormat(
    use24Hour ? 'HH:00' : 'h a',
    'en',
  ).format(localDateTime(seconds, timezone));

  String weekday(String date) =>
      _dateFormat('EEE').format(DateTime.parse(date));

  DateFormat _dateFormat(String pattern) {
    // This initializer installs bundled data synchronously.
    unawaited(_datesReady);
    return DateFormat(null, locale).addPattern(pattern);
  }

  String age(Duration age) {
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${number(age.inMinutes)} min ago';
    return '${number(age.inHours)} hr ago';
  }
}
