class ApiError implements Exception {
  final int status;
  final String code;
  const ApiError(this.status, this.code);
  bool get retryable => status == 0 || status == 429 || status >= 500;
  @override
  String toString() => 'ApiError($status)';
}
