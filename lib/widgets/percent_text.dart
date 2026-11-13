import 'package:material_ui/material_ui.dart';

/// Displays [number] followed by a `%` glyph styled like the clock's seconds
/// readout (slightly smaller and 70% foreground opacity).
class PercentText extends StatelessWidget {
  const PercentText(
    this.number, {
    super.key,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.unitSize,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String number;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final double? unitSize;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Builds a [TextSpan] for [number]`%` using the muted smaller `%` style.
  static TextSpan span(
    BuildContext context,
    String number, {
    TextStyle? style,
    String prefix = '',
    String suffix = '',
    double? unitSize,
  }) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final baseSize = base.fontSize ?? 14;
    final unitStyle = TextStyle(
      fontSize: unitSize ?? baseSize * 0.8,
      color: base.color?.withValues(alpha: 0.7),
    );
    return TextSpan(
      style: base,
      children: [
        if (prefix.isNotEmpty) TextSpan(text: prefix),
        TextSpan(text: number),
        TextSpan(text: '%', style: unitStyle),
        if (suffix.isNotEmpty) TextSpan(text: suffix),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    return Text.rich(
      span(
        context,
        number,
        style: resolved,
        prefix: prefix,
        suffix: suffix,
        unitSize: unitSize,
      ),
      style: resolved,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
