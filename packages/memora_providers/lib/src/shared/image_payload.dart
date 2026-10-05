import 'dart:convert';
import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

/// Largest image any adapter sends unless a provider sets a lower limit.
const defaultMaxImageBytes = 20 * 1024 * 1024;

/// An image checked and encoded for a request body.
///
/// Memora doesn't resize originals before sending them, so this guard turns
/// an oversized or unsupported file into a content error the queue records
/// as a failure instead of a request the provider rejects later.
class ImagePayload {
  ImagePayload._(this.bytes, this.mimeType);

  factory ImagePayload.of(
    Uint8List bytes,
    String mimeType, {
    required String providerId,
    int maxBytes = defaultMaxImageBytes,
    int? maxEncodedBytes,
    Set<String>? supportedMimeTypes,
  }) {
    var mime = mimeType.trim().toLowerCase();
    if (mime == 'image/jpg') mime = 'image/jpeg';

    if (bytes.isEmpty) {
      throw AiContentException(
        'The image file is empty',
        providerId: providerId,
      );
    }
    if (!mime.startsWith('image/')) {
      throw AiContentException(
        'Only images can be analyzed, not $mime',
        providerId: providerId,
      );
    }
    if (supportedMimeTypes != null && !supportedMimeTypes.contains(mime)) {
      throw AiContentException(
        'This provider does not accept $mime images',
        providerId: providerId,
      );
    }
    // Providers that cap the whole request count base64, which is 4 bytes
    // per 3 bytes of file.
    final effectiveMax = maxEncodedBytes == null
        ? maxBytes
        : _min(maxBytes, (maxEncodedBytes ~/ 4) * 3);
    if (bytes.length > effectiveMax) {
      final mb = (effectiveMax / (1024 * 1024)).toStringAsFixed(1);
      throw AiContentException(
        'The image is larger than the $mb MB this provider accepts',
        providerId: providerId,
      );
    }
    return ImagePayload._(bytes, mime);
  }

  final Uint8List bytes;
  final String mimeType;

  late final String base64Data = base64Encode(bytes);

  String get dataUri => 'data:$mimeType;base64,$base64Data';
}

int _min(int a, int b) => a < b ? a : b;
