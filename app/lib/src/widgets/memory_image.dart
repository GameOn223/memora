import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';
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
      codec: decodeBytes(key.files.readBytes(key.path), decode),
      scale: 1,
      debugLabel: key.path,
    );
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

/// Loads a thumbnail for one device gallery image, cached by its uri.
@immutable
class DeviceThumbnailImage extends ImageProvider<DeviceThumbnailImage> {
  const DeviceThumbnailImage(this.gallery, this.uri);

  final GalleryService gallery;
  final String uri;

  @override
  Future<DeviceThumbnailImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DeviceThumbnailImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: decodeBytes(key.gallery.thumbnail(key.uri), decode),
      scale: 1,
      debugLabel: key.uri,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceThumbnailImage &&
      identical(other.gallery, gallery) &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(identityHashCode(gallery), uri);

  @override
  String toString() => 'DeviceThumbnailImage($uri)';
}

/// Turns loaded bytes into a codec, failing loudly on an empty file.
Future<ui.Codec> decodeBytes(
  Future<Uint8List> bytes,
  ImageDecoderCallback decode,
) async {
  final data = await bytes;
  if (data.isEmpty) throw StateError('The image is empty');
  return decode(await ui.ImmutableBuffer.fromUint8List(data));
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
  });

  /// Relative path in app storage. Null shows the placeholder.
  final String? path;
  final BoxFit fit;
  final Alignment alignment;
  final double stripe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    if (p == null) return StripedPlaceholder(stripe: stripe);
    return ImageOrStripes(
      image: MemoraFileImage(ref.watch(appServicesProvider).images, p),
      fit: fit,
      alignment: alignment,
      stripe: stripe,
    );
  }
}

/// Shows a gallery image on the Add screen.
class DeviceImageView extends ConsumerWidget {
  const DeviceImageView({super.key, required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ImageOrStripes(
      image: DeviceThumbnailImage(ref.watch(appServicesProvider).gallery, uri),
    );
  }
}

/// An image that falls back to the striped placeholder while it loads and
/// when it cannot be read.
class ImageOrStripes extends StatelessWidget {
  const ImageOrStripes({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.stripe = 6,
  });

  final ImageProvider image;
  final BoxFit fit;
  final Alignment alignment;
  final double stripe;

  @override
  Widget build(BuildContext context) {
    final placeholder = StripedPlaceholder(stripe: stripe);
    return Image(
      image: image,
      fit: fit,
      alignment: alignment,
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
