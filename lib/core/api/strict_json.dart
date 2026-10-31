import 'dart:convert';

// Validate duplicate keys and nesting before the SDK decoder materialises JSON.
// String/number decoding remains the SDK implementation; no custom crypto.
Object? decodeStrictJson(String text) {
  final scan = _JsonShape(text);
  scan.value(0);
  scan.space();
  if (scan.offset != text.length) throw const FormatException('Trailing JSON');
  return jsonDecode(text);
}

class _JsonShape {
  final String text;
  int offset = 0;
  _JsonShape(this.text);
  void space() {
    while (offset < text.length && ' \n\r\t'.contains(text[offset])) {
      offset++;
    }
  }

  String string() {
    final start = offset++;
    bool escaped = false;
    while (offset < text.length) {
      final c = text[offset++];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        final v = jsonDecode(text.substring(start, offset)) as String;
        if (v.contains('\u0000')) throw const FormatException('NUL');
        return v;
      }
    }
    throw const FormatException('String');
  }

  void take(String expected) {
    space();
    if (offset >= text.length || text[offset++] != expected) {
      throw const FormatException('JSON shape');
    }
  }

  void value(int depth) {
    if (depth > 32) throw const FormatException('JSON nesting');
    space();
    if (offset >= text.length) throw const FormatException('JSON end');
    final c = text[offset];
    if (c == '{') {
      offset++;
      space();
      final keys = <String>{};
      if (offset < text.length && text[offset] == '}') {
        offset++;
        return;
      }
      while (true) {
        space();
        if (offset >= text.length || text[offset] != '"') {
          throw const FormatException('JSON key');
        }
        if (!keys.add(string())) throw const FormatException('Duplicate key');
        take(':');
        value(depth + 1);
        space();
        if (offset < text.length && text[offset] == '}') {
          offset++;
          return;
        }
        take(',');
      }
    } else if (c == '[') {
      offset++;
      space();
      if (offset < text.length && text[offset] == ']') {
        offset++;
        return;
      }
      var count = 0;
      while (true) {
        if (++count > 50) throw const FormatException('Collection limit');
        value(depth + 1);
        space();
        if (offset < text.length && text[offset] == ']') {
          offset++;
          return;
        }
        take(',');
      }
    } else if (c == '"') {
      string();
    } else {
      final start = offset;
      while (offset < text.length && !',]} \n\r\t'.contains(text[offset])) {
        offset++;
      }
      if (start == offset) throw const FormatException('JSON value');
      jsonDecode(text.substring(start, offset));
    }
  }
}
