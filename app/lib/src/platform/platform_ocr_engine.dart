import 'package:memora_core/memora_core.dart';

import 'messages.g.dart';

/// [OcrEngine] backed by ML Kit text recognition on the device.
class PlatformOcrEngine implements OcrEngine {
  PlatformOcrEngine({OcrHostApi? host}) : _host = host ?? OcrHostApi();

  final OcrHostApi _host;

  @override
  Future<OcrResult> recognize(String absoluteImagePath) async =>
      ocrResultFrom(await _host.recognize(absoluteImagePath));
}

OcrResult ocrResultFrom(List<OcrBlockMessage> blocks) => OcrResult(
  blocks: [
    for (final block in blocks)
      OcrBlock(
        lines: [
          for (final line in block.lines)
            OcrLine(
              text: line.text,
              left: line.left,
              top: line.top,
              right: line.right,
              bottom: line.bottom,
            ),
        ],
      ),
  ],
);
