class AppConfig {
  final Uri? apiOrigin;
  AppConfig._(this.apiOrigin);
  factory AppConfig.parse(String origin) {
    if (origin.isEmpty) return AppConfig._(null);
    final u = Uri.tryParse(origin);
    if (u == null ||
        u.scheme != 'https' ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.path.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment ||
        u.port < 1 ||
        u.port > 65535 ||
        origin != u.toString()) {
      throw const FormatException('HTTPS origin required');
    }
    return AppConfig._(u);
  }
  bool get configured => apiOrigin != null;
}
