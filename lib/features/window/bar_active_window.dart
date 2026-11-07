import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_tooltip.dart';
import '../hyprland/hyprland_backend.dart';

/// Figma "Active Window Info": app ID above the window title.
class BarActiveWindow extends StatelessWidget {
  const BarActiveWindow({super.key, this.backend, this.showAppName = true});

  /// Fixed so title changes never shift neighbouring pills.
  static const width = 128.0;

  final HyprlandBackend? backend;
  final bool showAppName;

  @override
  Widget build(BuildContext context) => backend == null
      ? _content(context)
      : ListenableBuilder(
          listenable: backend!,
          builder: (context, _) => _content(context),
        );

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final window = backend?.currentWindow;
    if (window == null || backend?.error != null) {
      return const SizedBox.shrink();
    }
    final title = window.title.isEmpty ? window.appId : window.title;
    if (title.isEmpty) return const SizedBox.shrink();
    // Two lines no longer fit the bar at large text scales.
    final appName =
        showAppName &&
        window.appId.isNotEmpty &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.4;
    TextStyle? style(double size, Color color) =>
        theme.textTheme.labelMedium?.copyWith(
          fontSize: size,
          fontWeight: .w500,
          height: 1,
          letterSpacing: 0,
          color: color,
        );
    return BarTooltip(
      message: title,
      child: Column(
        mainAxisAlignment: .center,
        crossAxisAlignment: .start,
        children: [
          if (appName)
            Text(
              window.appId,
              maxLines: 1,
              overflow: .ellipsis,
              style: style(10, colors.secondary),
            ),
          Text(
            title,
            maxLines: 1,
            overflow: .ellipsis,
            style: style(14, colors.primary),
          ),
        ],
      ),
    );
  }
}
