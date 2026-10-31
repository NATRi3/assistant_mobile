import 'dart:convert';

import 'package:flutter/services.dart';

class DesignTokens {
  final Map<String, dynamic> data;
  DesignTokens(this.data);
  static Future<DesignTokens> load() async => DesignTokens(
    jsonDecode(await rootBundle.loadString('design/tokens/semantic.json'))
        as Map<String, dynamic>,
  );
  Color color(Brightness brightness, String name) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';
    final value = data['semantic'][mode][name] as String;
    return Color(int.parse(value.substring(1), radix: 16) | 0xff000000);
  }
}
