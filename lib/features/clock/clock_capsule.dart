import 'package:material_ui/material_ui.dart';

const _timeWidth = 60.0;
const _horizontalPadding = 16.0;
const _spacing = 8.0;
const _separatorSize = 4.0;
const _minimumWidthWithDate =
    _timeWidth + 2 * (_horizontalPadding + _spacing) + _separatorSize;

class ClockCapsule extends StatelessWidget {
  const ClockCapsule({
    super.key,
    required this.time,
    required this.showSeconds,
  });

  final DateTime time;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: Theme.of(context)
          .textTheme
          .labelLarge
          ?.fontFamilyFallback,
      fontSize: 15,
      fontWeight: .w500,
      height: 1.25,
      letterSpacing: 0,
      color: colors.primary,
    );
    String pad(int value) => value.toString().padLeft(2, '0');

    return Material(
      color: colors.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 32,
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: .symmetric(
              horizontal: ((constraints.maxWidth - _timeWidth) / 2).clamp(
                0.0,
                _horizontalPadding,
              ),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: _spacing,
              children: [
                SizedBox(
                  width: _timeWidth,
                  child: FittedBox(
                    fit: .scaleDown,
                    alignment: .centerRight,
                    child: Text.rich(
                      TextSpan(
                        text: '${pad(time.hour)}:${pad(time.minute)}',
                        children: [
                          if (showSeconds)
                            TextSpan(
                              text: ':${pad(time.second)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.primary.withValues(alpha: 0.7),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                      style: style,
                    ),
                  ),
                ),
                if (constraints.maxWidth > _minimumWidthWithDate) ...[
                  SizedBox.square(
                    dimension: _separatorSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: .circle,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _dateLabel(time),
                      style: style,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month-$day ${weekdays[date.weekday - 1]}';
  }
}
