import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import 'bar_pill_layout.dart';
import 'bar_preference_models.dart';

/// Actions every pill shares: how its card opens and where it sits. The
/// layout editor offers them from each pill's context menu.
List<Widget> barPillMenu(
  String id,
  BarLayout layout,
  ValueChanged<BarLayout>? set,
) {
  final group = layout.groups.indexWhere((pills) => pills.contains(id));
  final hidden = group < 0;
  final click = layout.clickCards.contains(id);
  VoidCallback? action(BarLayout Function() next) =>
      set == null ? null : () => set(next());
  BarLayout trigger(bool click) => layout.copyWith(
    clickCards: [
      for (final card in barCardPillIds)
        if (card == id ? click : layout.clickCards.contains(card)) card,
    ],
  );
  return [
    if (barCardPillIds.contains(id)) ...[
      MenuItemButton(
        leadingIcon: Icon(
          click ? Icons.radio_button_unchecked : Icons.radio_button_checked,
        ),
        trailingIcon: const Icon(Icons.mouse_outlined),
        onPressed: click ? action(() => trigger(false)) : null,
        child: const Text('Open card on hover'),
      ),
      MenuItemButton(
        leadingIcon: Icon(
          click ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        trailingIcon: const Icon(Icons.ads_click_rounded),
        onPressed: click ? null : action(() => trigger(true)),
        child: const Text('Open card on click'),
      ),
      const Divider(height: 8),
    ],
    if (hidden)
      MenuItemButton(
        leadingIcon: const Icon(Icons.visibility_outlined),
        onPressed: action(() => layout.insertGroup(id, layout.groups.length)),
        child: const Text('Show in new group'),
      )
    else ...[
      MenuItemButton(
        leadingIcon: Icon(
          layout.center == group
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
        ),
        onPressed: action(
          () => layout.withCenter(layout.center == group ? null : group),
        ),
        child: const Text('Center its group'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.call_split_rounded),
        onPressed: layout.groups[group].length > 1
            ? action(() => layout.insertGroup(id, group + 1))
            : null,
        child: const Text('Move to own group'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.visibility_off_outlined),
        onPressed: id == 'sidebar' ? null : action(() => layout.hidePill(id)),
        child: const Text('Hide'),
      ),
    ],
  ];
}

/// Settings that belong to the selected pill alone.
class BarPillInspector extends StatelessWidget {
  const BarPillInspector({super.key, required this.id, required this.options});

  final String id;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) => options.isEmpty
      ? const SizedBox(width: double.infinity)
      : SettingsGroup(title: barPillNames[id]!, children: options);
}
