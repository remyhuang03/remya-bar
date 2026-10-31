import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../../bar_theme.dart';
import 'bar_popup.dart';

class BarPopupApp extends StatefulWidget {
  const BarPopupApp({super.key});

  @override
  State<BarPopupApp> createState() => _BarPopupAppState();
}

class _BarPopupAppState extends State<BarPopupApp> {
  Map<Object?, Object?>? _content;

  @override
  void initState() {
    super.initState();
    BarPopup.channel.setMethodCallHandler((call) async {
      if (call.method != 'content') throw MissingPluginException();
      if (mounted) {
        setState(() => _content = call.arguments as Map<Object?, Object?>);
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
    final theme = RemyaTheme.fromMap(
      Map<String, dynamic>.from(content['theme'] as Map),
    );
    final data = content['data'] as Map;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: barTheme(theme.theme(.light)),
      darkTheme: barTheme(theme.theme(.dark)),
      themeMode: theme.mode,
      home: switch (content['kind']) {
        'tooltip' => _TooltipContent(
          message: data['message'] as String,
          scale: (data['scale'] as num).toDouble(),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

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
