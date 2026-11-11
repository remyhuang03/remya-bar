import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import 'ai_quota_ring.dart';
import 'ai_usage_backend.dart';
import 'ai_usage_data.dart';

class BarAiQuota extends StatelessWidget {
  const BarAiQuota({super.key, required this.backend});

  final AiUsageBackend backend;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final data = backend.data;
    final providers = aiPillProviders(data, now);
    final scheme = Theme.of(context).colorScheme;
    return BarPill(
      color: scheme.surfaceContainerHighest,
      padding: const .only(left: 2, right: 12),
      expandedPadding: const .only(left: 10, right: 16),
      semanticsLabel: 'AI Quota',
      semanticsHint: 'Open AI Usage',
      onSecondaryTap: backend.refresh,
      card: BarPillCard(
        kind: aiUsageKind,
        size: const Size(420, 826),
        openOnTap: true,
        data: {...data, 'tick': backend.tick, 'refreshing': backend.refreshing},
      ),
      builder: (context, state) => FittedBox(
        fit: .scaleDown,
        child: Row(
          mainAxisSize: .min,
          spacing: state.expanded ? 14 : 8,
          children: [
            for (final (index, provider) in providers.indexed)
              _Segment(
                key: ValueKey(provider.id),
                provider: provider,
                index: index,
                state: state,
                showUsed: data['showUsed'] == true,
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.provider,
    required this.index,
    required this.state,
    required this.showUsed,
  });

  final AiQuotaProvider provider;
  final int index;
  final BarPillState state;
  final bool showUsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final windows = provider.pillWindows;
    final tightest = provider.tightest;
    final values = state.expanded ? windows : [?tightest];
    final reset = state.expanded || tightest?.low == true
        ? tightest?.resetShort
        : null;
    final label = [
      provider.name.toUpperCase(),
      if (windows.isNotEmpty)
        windows.map((window) => window.cadence).join(' / '),
    ].join(' · ');
    final text = values.isEmpty
        ? '—'
        : values.map((window) => window.percent).join(' / ');
    final dim = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.onSurfaceVariant, fontSize: 12, height: 1.25);
    return Semantics(
      label: provider.tooltip,
      child: Opacity(
        opacity: tightest == null ? .6 : 1,
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            AiQuotaRing(provider, showUsed: showUsed, index: index),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 114),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  if (state.expanded)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: dim.copyWith(
                        fontSize: 10,
                        fontWeight: .w600,
                        letterSpacing: .4,
                      ),
                    ),
                  ClipRect(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: .centerLeft,
                        children: [
                          for (final child in previous)
                            Positioned.fill(child: child),
                          ?current,
                        ],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, .6),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text.rich(
                        key: ValueKey((text, state.expanded)),
                        TextSpan(
                          children: [
                            if (values.isEmpty) const TextSpan(text: '—'),
                            for (final (index, window) in values.indexed) ...[
                              if (index > 0) const TextSpan(text: ' / '),
                              TextSpan(
                                text: window.percent,
                                style: window.low
                                    ? TextStyle(color: colors.error)
                                    : null,
                              ),
                            ],
                            if (reset != null)
                              TextSpan(text: '  $reset', style: dim),
                          ],
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: dim.copyWith(
                          fontSize: 14,
                          fontWeight: .w500,
                          color: state.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
