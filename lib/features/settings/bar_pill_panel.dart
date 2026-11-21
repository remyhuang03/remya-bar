import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import 'bar_preference_models.dart';
import 'bar_settings_entry.dart';

/// Settings pages that belong to a pill: Bar's own pages, or Remya Settings
/// pages when [core] is set.
const _pages = {
  'weather': (page: 'weather', title: 'Weather settings', core: false),
  'notifications': (
    page: 'notifications',
    title: 'Notification settings',
    core: false,
  ),
  'ai-usage': (page: 'ai-ring', title: 'AI quota rings', core: false),
  'clock': (page: 'date-time', title: 'Date & time', core: true),
  'battery': (page: 'power', title: 'Power', core: true),
};

/// The rows of a pill's panel, in the same order for every pill: how its
/// card opens, its own [options], then its settings page. Empty when the
/// pill has nothing to set.
List<Widget> barPillPanel(
  String id, {
  required BarLayout layout,
  required List<Widget> options,
  required ValueChanged<BarLayout>? onChanged,
}) => [
  if (barCardPillIds.contains(id))
    SettingRow(
      id: 'trigger',
      label: const SettingLabel('Open card'),
      control: SettingsSegmentedButton<bool>(
        segments: const [
          SettingsSegment(false, 'Hover', icon: Icon(Icons.mouse_outlined)),
          SettingsSegment(true, 'Click', icon: Icon(Icons.ads_click_rounded)),
        ],
        selected: layout.clickCards.contains(id),
        onSelected: onChanged == null
            ? null
            : (click) => onChanged(
                layout.copyWith(
                  clickCards: [
                    for (final card in barCardPillIds)
                      if (card == id ? click : layout.clickCards.contains(card))
                        card,
                  ],
                ),
              ),
      ),
    ),
  ...options,
  if (_pages[id] case final link?)
    SettingsLinkRow(
      icon: Icons.settings_outlined,
      title: link.title,
      external: link.core,
      onTap: () => link.core
          ? openRemyaSettings(page: link.page)
          : openBarSettings(page: link.page),
    ),
];
