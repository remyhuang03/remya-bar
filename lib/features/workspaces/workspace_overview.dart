import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class WorkspaceOverview extends StatelessWidget {
  const WorkspaceOverview({
    super.key,
    required this.workspaces,
    required this.onAction,
  });

  final List<Object?> workspaces;
  final Future<void> Function(Map<String, Object?>) onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            onAction({'action': 'close'}),
      },
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(20),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: .antiAlias,
        child: ListView(
          shrinkWrap: true,
          padding: const .symmetric(vertical: 8),
          children: [
            Padding(
              padding: const .fromLTRB(16, 8, 16, 8),
              child: Text(
                'Workspaces',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final row in workspaces)
              if (row case {
                'id': final int id,
                'name': final String name,
                'owner': final String owner,
                'count': final int count,
                'active': final bool active,
              })
                ListTile(
                  autofocus: active,
                  selected: active,
                  selectedTileColor: colors.secondaryContainer,
                  title: Text('Workspace $name'),
                  subtitle: Text(
                    '$owner\n$count ${count == 1 ? 'window' : 'windows'}',
                  ),
                  onTap: () =>
                      onAction({'action': 'workspace.switch', 'id': id}),
                ),
          ],
        ),
      ),
    );
  }
}
