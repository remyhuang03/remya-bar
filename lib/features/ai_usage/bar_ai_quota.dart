import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import '../../widgets/percent_text.dart';
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
                ringOrder: data['ringOrder'] as String? ?? '5h-outer',
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
    required this.ringOrder,
  });

  final AiQuotaProvider provider;
  final int index;
  final BarPillState state;
  final bool showUsed;
  final String ringOrder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final windows = provider.pillWindows;
    final tightest = provider.tightest;
    final values = state.expanded ? windows : [?tightest];
    final reset = state.expanded || tightest?.low == true
        ? tightest?.resetShort
        : null;
    final providerName = provider.id == 'antigravity'
        ? 'AGY'
        : provider.name.toUpperCase();
    final label = [
      providerName,
      if (windows.isNotEmpty)
        windows.map((window) => window.cadence).join(' / '),
    ].join(' · ');
    final text = values.isEmpty
        ? '—'
        : values
              .map((window) => window.percentText(showUsed: showUsed))
              .join(' / ');
    final dim = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.onSurfaceVariant, fontSize: 12, height: 1.25);
    final valueStyle = dim.copyWith(
      fontSize: 14,
      fontWeight: .w500,
      color: state.foreground,
    );
    return Semantics(
      label: provider.tooltipText(showUsed: showUsed),
      child: Opacity(
        opacity: tightest == null ? .6 : 1,
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            AiQuotaRing(
              provider,
              showUsed: showUsed,
              ringOrder: ringOrder,
              index: index,
            ),
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
                              PercentText.span(
                                context,
                                '${window.percentValue(showUsed: showUsed)}',
                                style: valueStyle.copyWith(
                                  color: window.low
                                      ? colors.error
                                      : valueStyle.color,
                                ),
                              ),
                            ],
                            if (reset != null)
                              TextSpan(text: '  $reset', style: dim),
                          ],
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: valueStyle,
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
