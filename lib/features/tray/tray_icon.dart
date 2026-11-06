import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class TrayIcon extends StatefulWidget {
  const TrayIcon({super.key, required this.data, required this.size});
  final Map<Object?, Object?> data;
  final double size;

  Uint8List? get argb => data['argb'] as Uint8List?;

  @override
  State<TrayIcon> createState() => _TrayIconState();
}

class _TrayIconState extends State<TrayIcon> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(TrayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.argb, widget.argb) ||
        oldWidget.data['width'] != widget.data['width'] ||
        oldWidget.data['height'] != widget.data['height']) {
      _decode();
    }
  }

  void _decode() {
    final argb = widget.argb;
    final generation = ++_generation;
    if (argb == null || argb.isEmpty) {
      _image?.dispose();
      _image = null;
      return;
    }
    final rgba = Uint8List(argb.length);
    for (var index = 0; index < rgba.length; index += 4) {
      rgba[index] = argb[index + 1];
      rgba[index + 1] = argb[index + 2];
      rgba[index + 2] = argb[index + 3];
      rgba[index + 3] = argb[index];
    }
    ui.decodeImageFromPixels(
      rgba,
      widget.data['width'] as int,
      widget.data['height'] as int,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attention = widget.data['attention'] == true;
    final size = widget.size;
    final fallback = Icon(
      attention ? Icons.notification_important_rounded : Icons.apps_rounded,
      size: size,
      color: attention ? Theme.of(context).colorScheme.error : null,
    );
    final bytes = widget.data['png'] as Uint8List?;
    final image = _image;
    final pixels = size * MediaQuery.devicePixelRatioOf(context);
    final raw = image == null
        ? fallback
        : RawImage(
            image: image,
            width: size,
            height: size,
            fit: .contain,
            filterQuality: .medium,
          );
    return ClipRRect(
      borderRadius: .circular(4),
      child:
          bytes != null &&
              (image == null || image.width < pixels || image.height < pixels)
          ? Image.memory(
              bytes,
              width: size,
              height: size,
              fit: .contain,
              filterQuality: .medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => raw,
            )
          : raw,
    );
  }
}
