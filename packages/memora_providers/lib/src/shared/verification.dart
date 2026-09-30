import 'package:memora_core/memora_core.dart';

/// User turn text sent with the image for [VisionService.verify].
const verifyUserText = 'Check the field in this image.';

/// Reads `{confirmed, observed_value}` leniently.
VerificationResult parseVerification(Map<String, Object?> json) {
  final confirmed = switch (json['confirmed']) {
    true || 'true' => true,
    _ => false,
  };
  final observed = switch (json['observed_value']) {
    final String s when s.trim().isNotEmpty => s.trim(),
    final num n => n.toString(),
    _ => null,
  };
  return VerificationResult(confirmed: confirmed, observedValue: observed);
}
