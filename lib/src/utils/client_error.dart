class ClientError implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final dynamic details;

  ClientError({
    required this.message,
    this.code,
    this.statusCode,
    this.details,
  });

  @override
  String toString() {
    final parts = ['ClientError: $message'];
    if (code != null) parts.add('Code: $code');
    if (statusCode != null) parts.add('Status: $statusCode');
    if (details != null) parts.add('Details: $details');
    return parts.join(', ');
  }
}
