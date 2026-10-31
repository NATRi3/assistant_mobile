// All accepted wire objects are deep immutable. Diagnostics never print bodies.
Object? freezeJson(Object? v) => switch (v) {
  Map m => Map<String, Object?>.unmodifiable(
    m.map((k, v) => MapEntry(k as String, freezeJson(v))),
  ),
  List l => List<Object?>.unmodifiable(l.map(freezeJson)),
  _ => v,
};
Map<String, Object?> objectJson(Object? v) {
  if (v is! Map) throw const FormatException('Invalid object');
  return Map<String, Object?>.from(v);
}
