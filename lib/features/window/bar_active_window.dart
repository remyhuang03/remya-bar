import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_tooltip.dart';
import '../hyprland/hyprland_backend.dart';

class BarActiveWindow extends StatelessWidget {
  const BarActiveWindow({super.key, this.backend});

  final HyprlandBackend? backend;

  @override
  Widget build(BuildContext context) => backend == null
      ? _content(context)
      : ListenableBuilder(
          listenable: backend!,
          builder: (context, _) => _content(context),
        );

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final window = backend?.currentWindow;
    if (window == null || backend?.error != null) {
      return const SizedBox.shrink();
    }
    final title = window.title.isEmpty ? window.appId : window.title;
    final subtitle = window.appId.isEmpty ? title : window.appId;
    if (title.isEmpty) return const SizedBox.shrink();
    return BarTooltip(
      message: title,
      child: Column(
        mainAxisAlignment: .center,
        crossAxisAlignment: .start,
        children: [
          Text(
            MediaQuery.textScalerOf(context).scale(1) <= 1.4 ? subtitle : title,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1,
            ),
          ),
          if (MediaQuery.textScalerOf(context).scale(1) <= 1.4)
            Text(
              title,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(height: 1),
            ),
        ],
      ),
    );
  }
}
