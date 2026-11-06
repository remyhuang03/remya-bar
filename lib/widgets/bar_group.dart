import 'package:material_ui/material_ui.dart';

/// A compact Material surface inside the 40-pixel bar.
class BarGroup extends StatelessWidget {
  const BarGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Padding(
      padding: const .symmetric(vertical: 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: Padding(padding: const .symmetric(horizontal: 8), child: child),
      ),
    ),
  );
}
