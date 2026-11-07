import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

class MediaArtwork extends StatefulWidget {
  const MediaArtwork({
    super.key,
    required this.url,
    required this.styleVariant,
    required this.builder,
  });

  final String url;
  final DynamicSchemeVariant styleVariant;
  final Widget Function(BuildContext, ImageProvider?, ColorScheme?) builder;

  @override
  State<MediaArtwork> createState() => _MediaArtworkState();
}

class _MediaArtworkState extends State<MediaArtwork> {
  String? _url;
  Brightness? _brightness;
  DynamicSchemeVariant? _variant;
  ImageProvider? _artwork;
  ColorScheme? _scheme;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(MediaArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveArtwork();
  }

  void _resolveArtwork() {
    final url = widget.url;
    final brightness = Theme.of(context).brightness;
    if (_url == url &&
        _brightness == brightness &&
        _variant == widget.styleVariant) {
      return;
    }
    _variant = widget.styleVariant;
    _url = url;
    _brightness = brightness;
    _scheme = null;
    _artwork = _artworkImage(url);
    final generation = ++_generation;
    final artwork = _artwork;
    if (artwork == null) return;
    unawaited(
      ColorScheme.fromImageProvider(
            provider: artwork,
            brightness: brightness,
            dynamicSchemeVariant: widget.styleVariant,
          )
          .then((scheme) {
            if (mounted && generation == _generation) {
              setState(() => _scheme = scheme);
            }
          })
          .catchError((Object error) {
            // Missing or unsupported cover art retains the owning Settings palette.
            if (mounted && generation == _generation) {
              setState(() => _scheme = null);
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _artwork, _scheme);
}

ImageProvider? _artworkImage(String source) {
  if (source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  ImageProvider image;
  if (uri.scheme == 'file' &&
      (uri.host.isEmpty || uri.host == 'localhost') &&
      uri.path.startsWith('/') &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    try {
      image = FileImage(File(uri.replace(host: '').toFilePath(windows: false)));
    } on ArgumentError {
      return null;
    }
  } else if ((uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    image = NetworkImage(uri.removeFragment().toString());
  } else {
    return null;
  }
  return ResizeImage(image, width: 256, height: 256, policy: .fit);
}
