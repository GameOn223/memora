import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../state/services.dart';
import 'striped_placeholder.dart';

/// Loads an image in app storage through [ImageFiles], cached by path.
@immutable
class MemoraFileImage extends ImageProvider<MemoraFileImage> {
  const MemoraFileImage(this.files, this.path);

  final ImageFiles files;
  final String path;

  @override
  Future<MemoraFileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    MemoraFileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: key.path,
    );
  }

  Future<ui.Codec> _load(
    MemoraFileImage key,
    ImageDecoderCallback decode,
  ) async {
    final Uint8List bytes = await key.files.readBytes(key.path);
    if (bytes.isEmpty) {
      throw StateError('Image at ${key.path} is empty');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is MemoraFileImage &&
      identical(other.files, files) &&
      other.path == path;

  @override
  int get hashCode => Object.hash(identityHashCode(files), path);

  @override
  String toString() => 'MemoraFileImage($path)';
}

/// Shows a stored image, or diagonal stripes until it has loaded or when
/// there is no image yet.
class MemoryImageView extends ConsumerWidget {
  const MemoryImageView({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.stripe = 6,
    this.cacheWidth,
  });

  /// Relative path in app storage. Null shows the placeholder.
  final String? path;
  final BoxFit fit;
  final Alignment alignment;
  final double stripe;

  /// Decode at this width in physical pixels to save memory in grids.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = StripedPlaceholder(stripe: stripe);
    final p = path;
    if (p == null) return placeholder;
    final files = ref.watch(appServicesProvider).images;
    ImageProvider provider = MemoraFileImage(files, p);
    if (cacheWidth != null) {
      provider = ResizeImage(
        provider,
        width: cacheWidth,
        policy: ResizeImagePolicy.fit,
      );
    }
    return Image(
      image: provider,
      fit: fit,
      alignment: alignment,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) {
        if (frame == null && !sync) return placeholder;
        return child;
      },
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}

/// Shows raw image bytes loaded on demand, such as gallery thumbnails.
class BytesImageView extends StatefulWidget {
  const BytesImageView({super.key, required this.load, this.cacheKey});

  final Future<Uint8List> Function() load;

  /// Changes when a different image should be loaded.
  final Object? cacheKey;

  @override
  State<BytesImageView> createState() => _BytesImageViewState();
}

class _BytesImageViewState extends State<BytesImageView> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(BytesImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _bytes = null;
      unawaited(_fetch());
    }
  }

  Future<void> _fetch() async {
    try {
      final bytes = await widget.load();
      if (mounted && bytes.isNotEmpty) setState(() => _bytes = bytes);
    } on Object {
      // Keep the placeholder.
    }
  }

  @override
  Widget build(BuildContext context) {
    const placeholder = StripedPlaceholder();
    final bytes = _bytes;
    if (bytes == null) return placeholder;
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? placeholder : child,
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}
