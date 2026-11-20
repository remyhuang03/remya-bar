import 'package:material_ui/material_ui.dart';

import '../../bar_theme.dart';
import '../../widgets/bar_pill.dart';
import '../../widgets/bar_tooltip.dart';
import '../popups/bar_card_surface.dart';
import '../popups/bar_popup.dart';
import 'weather_card.dart';
import 'weather_controller.dart';
import 'weather_presentation.dart';

class BarWeather extends StatelessWidget {
  const BarWeather({super.key, required this.weather});
  final WeatherController weather;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        if (!weather.enabled) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final remya = BarPopupScope.themeOf(context);
        final seed = currentWeatherSeed(weather);
        final colorPill = weather.settings['color-pill'] == true;
        final colors = BarCardSurface.colors(
          theme,
          colorPill ? seed : null,
          remya.styleVariant,
          contrastLevel: remya.contrast.level,
        );
        final format = WeatherFormat(context, weather.settings);
        final current = weather.snapshot?.current;
        final location = weather.location;
        final condition = weatherCondition(
          current?.condition,
          current?.weatherCode,
        );
        final unavailable = weather.result != null && weather.snapshot == null;
        final temperature = current?.temperatureC == null
            ? '—°'
            : format.temperature(
                current?.temperatureC,
                withUnit: weather.settings['show-unit'] == true,
              );
        final details = [
          if (location == null)
            'Choose a location'
          else if (current == null && weather.snapshot == null)
            '${location.name} · ${unavailable ? 'Weather unavailable' : 'Loading weather'}'
          else
            '${location.name} · $condition',
          if (current != null) ...[
            '${format.temperature(current.temperatureC, withUnit: true, precise: true)}'
                ' · Feels like ${format.temperature(current.feelsLikeC, withUnit: true, precise: true)}',
            'Weather valid at ${format.time(current.validAt, weather.snapshot!.timezone)}',
          ],
          if (weather.snapshot != null && weather.stale)
            'Showing saved weather',
          weatherSource,
        ].join('\n');

        final content = weather.settings['pill'];
        return BarTooltip(
          message: details,
          suppressWhenCardOpen: 'weather',
          showOnFocus: true,
          child: BarPill(
            scheme: colors,
            color: colors.surfaceContainerHigh,
            padding: const .symmetric(horizontal: 7),
            semanticsLabel: 'Weather. $details',
            semanticsHint: 'Open forecast',
            card: BarPillCard(
              kind: 'weather',
              size: const Size(420, 610),
              seedColor: seed,
              openOnTap: true,
              hoverOpens: false,
            ),
            builder: (context, state) => ExcludeSemantics(
              child: Row(
                mainAxisSize: .min,
                spacing: 4,
                children: [
                  if (content != 'temperature')
                    IconTheme.merge(
                      data: IconThemeData(color: state.foreground),
                      child: WeatherIcon(
                        current?.condition,
                        size: 24,
                        statusIcon: location == null
                            ? Icons.location_on_outlined
                            : unavailable
                            ? Icons.cloud_off_rounded
                            : null,
                      ),
                    ),
                  if (content != 'icon')
                    SizedBox(
                      width: 42,
                      child: FittedBox(
                        fit: .scaleDown,
                        alignment: .center,
                        child: Text(
                          temperature,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: barFontFamily,
                            fontFamilyFallback: barFontFamilyFallback,
                            fontWeight: .w400,
                            fontSize: 16,
                            color: state.foreground,
                          ),
                        ),
                      ),
                    ),
                  if (weather.snapshot != null && weather.stale)
                    Icon(
                      Icons.history_rounded,
                      size: 11,
                      color: state.foreground,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
