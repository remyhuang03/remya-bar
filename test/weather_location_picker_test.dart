import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/weather/weather_backend.dart';
import 'package:remya_bar/features/weather/weather_controller.dart';
import 'package:remya_bar/features/weather/weather_location_picker.dart';

class _Backend extends Fake implements WeatherBackend {
  final requests = <String, Completer<List<WeatherLocation>>>{};
  final languages = <String>[];

  @override
  Future<List<WeatherLocation>> search(
    String query, {
    required String language,
    String? countryCode,
  }) {
    languages.add(language);
    return (requests[query] = Completer()).future;
  }
}

class _Weather extends ChangeNotifier implements WeatherController {
  @override
  final _Backend backend = _Backend();

  @override
  WeatherLocation? location;
  @override
  String? locationRevision = 'original revision';
  @override
  String? get locationError => null;
  @override
  bool get savingLocation => false;

  String? savedRevision;

  @override
  Future<bool> select(WeatherLocation selected, String revision) async {
    location = selected;
    savedRevision = revision;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _showPicker(
  WidgetTester tester,
  _Weather weather, {
  required VoidCallback onClose,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: const .all(24),
            child: WeatherLocationPicker(controller: weather, onClose: onClose),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('debounces two-character searches and discards late matches', (
    tester,
  ) async {
    final weather = _Weather();
    tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    var closed = false;
    await _showPicker(tester, weather, onClose: () => closed = true);
    final field = find.byType(TextField);

    await tester.enterText(field, '台');
    await tester.pump(const Duration(milliseconds: 350));
    expect(weather.backend.requests, isEmpty);
    await tester.enterText(field, '台北');
    await tester.pump(const Duration(milliseconds: 349));
    expect(weather.backend.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(weather.backend.languages, ['zh']);

    await tester.enterText(field, '台中');
    await tester.pump(const Duration(milliseconds: 350));
    const taiChung = WeatherLocation(
      name: 'Taichung',
      latitude: 24.1477,
      longitude: 120.6736,
      region: 'Taichung',
      country: 'Taiwan',
    );
    weather.backend.requests['台中']!.complete([taiChung]);
    await tester.pumpAndSettle();
    weather.backend.requests['台北']!.complete(const [
      WeatherLocation(name: 'Taipei', latitude: 25.0, longitude: 121.5),
    ]);
    await tester.pump();
    expect(find.text('Taipei'), findsNothing);
    expect(find.text('Taichung, Taiwan'), findsOneWidget);

    weather.locationRevision = 'changed revision';
    await tester.tap(find.text('Taichung'));
    await tester.pump();
    expect(closed, isTrue);
    expect(weather.location, taiChung);
    expect(weather.savedRevision, 'original revision');
  });

  testWidgets('manual location needs an explicit save and valid coordinates', (
    tester,
  ) async {
    final weather = _Weather();
    var closed = false;
    await _showPicker(tester, weather, onClose: () => closed = true);
    await tester.tap(find.text('Enter coordinates'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), ' Polar station ');
    await tester.enterText(fields.at(1), '-90');
    await tester.enterText(fields.at(2), '180.01');

    final save = find.text('Save location');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a value from −180 to 180.'), findsOneWidget);
    expect(weather.location, isNull);
    expect(closed, isFalse);

    await tester.enterText(fields.at(2), '179,5');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(weather.location?.name, 'Polar station');
    expect(weather.location?.latitude, -90);
    expect(weather.location?.longitude, 179.5);
    expect(closed, isTrue);
  });
}
