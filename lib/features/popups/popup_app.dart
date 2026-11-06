import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../bar_theme.dart';
import '../media/media_preview.dart';
import '../battery/battery_card.dart';
import 'bar_card_surface.dart';
import 'bar_popup.dart';

class BarPopupApp extends StatefulWidget {
  const BarPopupApp({super.key});

  @override
  State<BarPopupApp> createState() => _BarPopupAppState();
}

class _BarPopupAppState extends State<BarPopupApp> {
  final _navigator = GlobalKey<NavigatorState>();
  Map<Object?, Object?>? _content;
  String? _actionError;
  bool _batteryActionPending = false;

  Future<void> _action(Map<String, Object?> action) async {
    final battery = _content?['kind'] == 'battery';
    if (battery && _batteryActionPending) return;
    if (battery) setState(() => _batteryActionPending = true);
    try {
      await BarPopup.action(action);
      if (mounted) setState(() => _actionError = null);
    } catch (error) {
      debugPrint('Popup action: $error');
      if (mounted) {
        setState(() => _actionError = 'Action failed. Please try again.');
      }
    } finally {
      if (battery && mounted) setState(() => _batteryActionPending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    BarPopup.channel.setMethodCallHandler((call) async {
      if (call.method != 'content') throw MissingPluginException();
      if (mounted) {
        setState(() {
          final next = call.arguments as Map<Object?, Object?>;
          if (_content?['kind'] != next['kind']) _actionError = null;
          _content = next;
        });
      }
    });
    BarPopup.channel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    BarPopup.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    final baseTheme = RemyaTheme.fromMap(
      Map<String, dynamic>.from(content['theme'] as Map),
    );
    final seed = _seedColor(content['seed']);
    final theme = seed == null
        ? baseTheme
        : RemyaTheme(
            styleVariant: baseTheme.styleVariant,
            mode: baseTheme.mode,
            seedColor: seed,
          );
    final data = content['data'] as Map;
    final kind = content['kind'] as String;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      builder: (context, child) => kind == 'tooltip'
          ? child!
          : MouseRegion(
              onEnter: (_) => BarPopup.enter(kind: kind),
              onExit: (_) {
                _navigator.currentState?.popUntil((route) => route.isFirst);
                BarPopup.leave(kind: kind);
              },
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: .linear((data['scale'] as num?)?.toDouble() ?? 1),
                ),
                child: child!,
              ),
            ),
      theme: barTheme(theme.theme(.light)),
      darkTheme: barTheme(theme.theme(.dark)),
      themeMode: theme.mode,
      home: switch (content['kind']) {
        'media' => MediaPreview(
          data: {...Map<String, Object?>.from(data), 'error': ?_actionError},
          onAction: _action,
          styleVariant: theme.styleVariant,
        ),
        'battery' => BarCardSurface(
          child: BatteryCard(
            data: {
              ...Map<String, Object?>.from(data),
              'error': ?_actionError,
              'pending': _batteryActionPending,
            },
            onAction: _action,
          ),
        ),
        'tooltip' => _TooltipContent(
          message: data['message'] as String,
          scale: (data['scale'] as num).toDouble(),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

Color? _seedColor(Object? rgb) =>
    rgb is int && rgb >= 0 && rgb <= 0xFFFFFF ? Color(0xFF000000 | rgb) : null;

class _TooltipContent extends StatelessWidget {
  const _TooltipContent({required this.message, required this.scale});
  final String message;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: .circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: .antiAlias,
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          textScaler: .linear(scale),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
