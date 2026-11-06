import 'package:material_ui/material_ui.dart';

class BarCardSurface extends StatelessWidget {
  const BarCardSurface({
    super.key,
    required this.child,
    this.seedColor,
    this.styleVariant = .tonalSpot,
  });

  final Widget child;
  final Color? seedColor;
  final DynamicSchemeVariant styleVariant;

  // Reserve room in the native popup for the Flutter-rendered shadow.
  static const shadowInsets = EdgeInsets.fromLTRB(40, 12, 40, 52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seed = seedColor;
    final colors = seed == null
        ? theme.colorScheme
        : ColorScheme.fromSeed(
            seedColor: seed,
            brightness: theme.brightness,
            dynamicSchemeVariant: styleVariant,
          );
    final shape = RoundedRectangleBorder(
      borderRadius: .circular(32),
      side: BorderSide(color: colors.surfaceContainerHighest),
    );
    final surface = Padding(
      padding: shadowInsets,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: .all(Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 12),
              blurRadius: 20,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Material(
          color: colors.surfaceContainer,
          shape: shape,
          clipBehavior: .antiAlias,
          child: SingleChildScrollView(padding: const .all(24), child: child),
        ),
      ),
    );
    return seed == null
        ? surface
        : Theme(
            data: theme.copyWith(colorScheme: colors),
            child: surface,
          );
  }
}
