class Constants {
  static const String defaultApiBaseUrl = 'https://api.anam.ai';
  static const String defaultApiVersion = '/v1';
  static const String clientName = 'flutter-sdk';
  static const String clientVersion = '0.0.1';

  static const Map<String, String> clientMetadata = {
    'client': clientName,
    'version': clientVersion,
  };

  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 3);
  static const int maxReconnectAttempts = 5;
}
