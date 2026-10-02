import 'dart:math' as math;
import 'dart:typed_data';

/// Copies numbers from a JSON array into an L2-normalized vector.
///
/// Throws [FormatException] when an entry isn't a number. A zero vector is
/// returned unchanged.
Float32List normalizedVector(List<Object?> values) {
  final doubles = List<double>.filled(values.length, 0);
  var sum = 0.0;
  for (var i = 0; i < values.length; i++) {
    final value = values[i];
    if (value is! num) {
      throw const FormatException('Embedding values must be numbers');
    }
    final d = value.toDouble();
    doubles[i] = d;
    sum += d * d;
  }
  final norm = math.sqrt(sum);
  final out = Float32List(values.length);
  for (var i = 0; i < doubles.length; i++) {
    out[i] = norm == 0 ? doubles[i] : doubles[i] / norm;
  }
  return out;
}
