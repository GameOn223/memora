import 'package:flutter/services.dart';
import 'package:memora_core/memora_core.dart';

import 'messages.g.dart' as bridge;

/// [Links] over the platform's link handler.
class PlatformLinks implements Links {
  PlatformLinks({bridge.LinksHostApi? host})
    : _host = host ?? bridge.LinksHostApi();

  final bridge.LinksHostApi _host;

  @override
  Future<bool> open(String url) async {
    try {
      return await _host.openUrl(url);
    } on PlatformException {
      // A link Memora would not open, or no handler for it. Either way the
      // caller shows the address so it can be typed by hand.
      return false;
    }
  }
}
