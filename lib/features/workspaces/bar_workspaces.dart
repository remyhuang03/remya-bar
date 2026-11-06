import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../hyprland/hyprland_backend.dart';

class BarWorkspaces extends StatefulWidget {
  const BarWorkspaces({super.key, this.backend});

  static const slotWidth = 26.0;
  static const width = 208.0;

  final HyprlandBackend? backend;

  @override
  State<BarWorkspaces> createState() => _BarWorkspacesState();
}

class _BarWorkspacesState extends State<BarWorkspaces> {
  // shortcut: Super-held number reveal needs a compositor key-event contract.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => widget.backend == null
      ? _content(context)
      : ListenableBuilder(
          listenable: widget.backend!,
          builder: (context, _) => _content(context),
        );

  Widget _content(BuildContext context) {
    final state = widget.backend;
    if (state == null || !state.connected || state.error != null) {
      return const SizedBox.shrink();
    }
    final slots = state.workspaceSlots;
    if (slots.isEmpty) return const SizedBox.shrink();
    final output = state.output;
    final currentName = state.allWorkspaces
        .where((workspace) => workspace.id == output?.activeWorkspaceId)
        .firstOrNull
        ?.name;
    final overlay = output?.specialWorkspaceId != null
        ? output?.specialWorkspaceName?.replaceFirst('special:', '') ??
              'Special'
        : (output?.activeWorkspaceId ?? 1) < 0
        ? currentName
        : null;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          unawaited(state.scroll(event.scrollDelta.dy > 0 ? 1 : -1));
        }
      },
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) {
          unawaited(state.toggleSpecial());
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: BarWorkspaces.width,
          height: 32,
          child: Stack(
            alignment: .center,
            children: [
              AnimatedOpacity(
                opacity: overlay != null && !_hovered ? .35 : 1,
                duration: const Duration(milliseconds: 200),
                child: _WorkspaceSlots(slots: slots, backend: state),
              ),
              if (overlay != null && !_hovered)
                IgnorePointer(
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const StadiumBorder(),
                    child: Padding(
                      padding: const .symmetric(horizontal: 12, vertical: 3),
                      child: Text(
                        overlay,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSlots extends StatelessWidget {
  const _WorkspaceSlots({required this.slots, required this.backend});

  final List<HyprlandWorkspaceSlot> slots;
  final HyprlandBackend backend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = slots.indexWhere((slot) => slot.active);
    return Stack(
      alignment: .centerLeft,
      fit: .expand,
      children: [
        Row(
          children: [
            for (var index = 0; index < slots.length; index++)
              SizedBox(
                width: BarWorkspaces.slotWidth,
                height: 26,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: slots[index].occupied
                        ? colors.secondaryContainer
                        : Colors.transparent,
                    borderRadius: .horizontal(
                      left: .circular(
                        index > 0 && slots[index - 1].occupied ? 0 : 13,
                      ),
                      right: .circular(
                        index + 1 < slots.length && slots[index + 1].occupied
                            ? 0
                            : 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (active >= 0)
          AnimatedPositioned(
            key: const ValueKey('workspace-active-indicator'),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            left: active * BarWorkspaces.slotWidth + 2,
            top: 5,
            width: 22,
            height: 22,
            child: Material(color: colors.primary, shape: const CircleBorder()),
          ),
        Row(
          children: [
            for (final slot in slots)
              _WorkspaceButton(slot: slot, backend: backend),
          ],
        ),
      ],
    );
  }
}

class _WorkspaceButton extends StatelessWidget {
  const _WorkspaceButton({required this.slot, required this.backend});

  final HyprlandWorkspaceSlot slot;
  final HyprlandBackend backend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = slot.active
        ? colors.onPrimary
        : slot.occupied
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    return Semantics(
      selected: slot.active,
      label: 'Workspace ${slot.name}, ${slot.windowCount} windows',
      child: IconButton(
        key: ValueKey('workspace-${slot.id}'),
        onPressed: slot.id != 0
            ? () => unawaited(backend.switchWorkspace(slot.id))
            : null,
        padding: .zero,
        constraints: const .tightFor(
          width: BarWorkspaces.slotWidth,
          height: BarWorkspaces.slotWidth,
        ),
        iconSize: 22,
        alignment: .center,
        visualDensity: .standard,
        style: const .new(
          tapTargetSize: .shrinkWrap,
          fixedSize: WidgetStatePropertyAll(
            Size.square(BarWorkspaces.slotWidth),
          ),
          shape: WidgetStatePropertyAll(CircleBorder()),
        ),
        icon: slot.occupied
            ? _WorkspaceIcon(
                path: slot.appId == null ? null : backend.iconPath(slot.appId!),
                color: color,
              )
            : Text(
                slot.id == 0 ? '—' : '${slot.id}',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color),
              ),
      ),
    );
  }
}

class _WorkspaceIcon extends StatelessWidget {
  const _WorkspaceIcon({required this.path, required this.color});

  final String? path;
  final Color color;

  @override
  Widget build(BuildContext context) => path == null
      ? Icon(Icons.apps_rounded, size: 22, color: color)
      : ClipOval(
          child: Image.file(
            File(path!),
            width: 22,
            height: 22,
            fit: .contain,
            color: color.withValues(alpha: .8),
            colorBlendMode: .color,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                Icon(Icons.apps_rounded, size: 22, color: color),
          ),
        );
}
