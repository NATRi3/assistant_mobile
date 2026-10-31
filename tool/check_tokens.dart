import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  final j = jsonDecode(
    File('design/tokens/semantic.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  double l(String h) {
    final rgb = [1, 3, 5]
        .map((i) => int.parse(h.substring(i, i + 2), radix: 16) / 255)
        .map(
          (v) => v <= 0.04045
              ? v / 12.92
              : pow((v + 0.055) / 1.055, 2.4).toDouble(),
        )
        .toList();
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
  }

  for (final mode in ['light', 'dark']) {
    for (final pair in j['contrastPairs'] as List) {
      final colors = j['semantic'][mode];
      final a = l(colors[pair['foreground']] as String),
          b = l(colors[pair['background']] as String);
      final ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05);
      if (ratio < (pair['minimum'] as num)) {
        throw StateError('Contrast fails: $mode ${pair['foreground']}');
      }
    }
  }
  stdout.writeln('Approved semantic contrast pairs pass in light/dark.');
}
