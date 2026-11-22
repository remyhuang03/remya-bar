import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tray/tray_icon.dart';

/// Resolves a real application icon or conversation avatar for a notification.
class NotificationLeading extends StatelessWidget {
  const NotificationLeading({
    super.key,
    required this.data,
    this.background,
    this.size = 40,
  });

  final Map data;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final critical = data['urgency'] == 2;
    final avatar = data['avatar'] == true && !critical;
    final hasPicture = NotificationPicture.hasImage(data);
    final bytes = data['icon'];
    final path = data['iconPath'];
    final symbolic = data['iconSymbolic'] == true;
    final hasIcon = bytes is Uint8List || path is String;

    Widget appIcon(double diameter) {
      final glyphMode = critical || symbolic || !hasIcon;
      final glyphSize = diameter * .6;
      final iconSize = glyphMode ? glyphSize : diameter;
      final foreground = critical
          ? colors.onErrorContainer
          : colors.onPrimaryContainer;
      final fallback = Icon(
        critical
            ? Icons.error_outline_rounded
            : Icons.chat_bubble_outline_rounded,
        size: glyphSize,
        color: foreground,
      );
      final icon = bytes is Uint8List
          ? Image.memory(
              bytes,
              width: iconSize,
              height: iconSize,
              fit: glyphMode ? .contain : .cover,
              color: glyphMode ? foreground : null,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            )
          : path is String
          ? Image.file(
              File(path),
              width: iconSize,
              height: iconSize,
              fit: glyphMode ? .contain : .cover,
              color: glyphMode ? foreground : null,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback;
      return ClipOval(
        child: Container(
          width: diameter,
          height: diameter,
          alignment: .center,
          color: glyphMode
              ? critical
                    ? colors.errorContainer
                    : colors.primaryContainer
              : null,
          child: icon,
        ),
      );
    }

    if (!avatar) return appIcon(size);
    final initials = ((data['summary'] as String?) ?? '')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final portrait = hasPicture
        ? NotificationPicture(
            data: data,
            width: size,
            height: size,
            radius: size / 2,
          )
        : Container(
            width: size,
            height: size,
            alignment: .center,
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              shape: .circle,
            ),
            child: Text(
              initials,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onTertiaryContainer,
                fontSize: size * .375,
              ),
            ),
          );
    if (!hasPicture || size != 40) return portrait;
    return Stack(
      clipBehavior: .none,
      children: [
        portrait,
        Positioned(
          left: 22,
          top: 22,
          child: Container(
            width: 20,
            height: 20,
            padding: const .all(2),
            decoration: BoxDecoration(
              color: background ?? colors.surfaceContainerHighest,
              shape: .circle,
            ),
            child: appIcon(16),
          ),
        ),
      ],
    );
  }
}

class NotificationPicture extends StatelessWidget {
  const NotificationPicture({
    super.key,
    required this.data,
    required this.width,
    required this.height,
    required this.radius,
  });

  static bool hasImage(Map data) =>
      data['imageArgb'] is Uint8List || data['image'] is Uint8List;

  final Map data;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = data['image'];
    return ClipRRect(
      borderRadius: .circular(radius),
      child: image is Uint8List
          ? Image.memory(
              image,
              width: width,
              height: height,
              fit: .cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : TrayIcon(
              data: {
                'argb': data['imageArgb'],
                'width': data['imageWidth'],
                'height': data['imageHeight'],
              },
              size: height,
              width: width,
              fit: .cover,
            ),
    );
  }
}
