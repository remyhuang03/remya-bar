import 'package:material_ui/material_ui.dart';

import '../battery/battery_card.dart';
import '../clock/datetime_card.dart';
import '../media/media_preview.dart';
import '../resources/resource_card.dart';
import 'bar_card_surface.dart';

typedef PopupAction = ValueChanged<Map<String, Object?>>;

class BarDetailCard extends StatelessWidget {
  const BarDetailCard({
    super.key,
    required this.kind,
    required this.data,
    required this.onAction,
    this.styleVariant = .tonalSpot,
    this.seedColor,
    this.emergence = const AlwaysStoppedAnimation(1),
  });

  final Animation<double> emergence;

  final DynamicSchemeVariant styleVariant;
  final Color? seedColor;
  final String kind;
  final Map<String, Object?> data;
  final PopupAction onAction;

  @override
  Widget build(BuildContext context) => kind == 'media'
      ? MediaPreview(
          data: data,
          onAction: onAction,
          styleVariant: styleVariant,
          seedColor: seedColor,
          pill: _pill(data['pill']),
          emergence: emergence,
        )
      : BarCardSurface(
          seedColor: seedColor,
          pill: _pill(data['pill']),
          emergence: emergence,
          styleVariant: styleVariant,
          child: switch (kind) {
            'resources' => ResourceCard(
              data: data,
              onOpenMonitor: () =>
                  onAction(const {'action': 'resources.monitor'}),
            ),
            'battery' => BatteryCard(data: data, onAction: onAction),
            'datetime' => DatetimeCard(
              data: data,
              onSettings: () => onAction(const {'action': 'datetime.settings'}),
            ),
            _ => const Text('Unavailable'),
          },
        );
}

Rect? _pill(Object? value) =>
    value is List &&
        value.length == 2 &&
        value[0] is int &&
        value[1] is int &&
        (value[1] as int) > 0
    ? Rect.fromLTWH(
        (value[0] as int).toDouble(),
        0,
        (value[1] as int).toDouble(),
        0,
      )
    : null;
