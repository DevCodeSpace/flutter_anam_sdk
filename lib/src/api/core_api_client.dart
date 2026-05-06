import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';

import '../models/persona_config.dart';
import '../utils/client_error.dart';
import '../utils/constants.dart';
import '../utils/correlation_id.dart';

class CoreApiClient {
  final String baseUrl;
  final String version;
  final String? apiKey;
  final String? sessionToken;
  final Logger _logger;
  final bool? disableBrains;

  CoreApiClient({
    required this.baseUrl,
    required this.version,
    this.apiKey,
    this.sessionToken,
    this.disableBrains,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Correlation-Id': CorrelationIdManager.generate(),
      ...Constants.clientMetadata,
    };

    if (sessionToken != null) {
      headers['Authorization'] = 'Bearer $sessionToken';
    } else if (apiKey != null) {
      headers['X-Api-Key'] = apiKey!;
    }

    return headers;
  }

  Future<Map<String, dynamic>> startSession({
    required PersonaConfig personaConfig,
  }) async {
    // Use the correct Anam API endpoint
    final url = Uri.parse('https://api.anam.ai/v1/engine/session');

    final requestBody = {
      'personaConfig': {
        'personaId': personaConfig.personaId,
        'disableBrains': disableBrains ?? false,
      },
    };

    _logger.d('Starting engine session at: $url');
    _logger.d('Request body: ${jsonEncode(requestBody)}');

    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(requestBody),
      );

      _logger.d('Response status: ${response.statusCode}');
      _logger.d('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _logger.d('Engine session created successfully');

        // Validate expected fields
        if (!data.containsKey('sessionId') ||
            !data.containsKey('engineHost') ||
            !data.containsKey('signallingEndpoint')) {
          throw ClientError(
            message: 'Invalid session response - missing required fields',
            details: data,
          );
        }

        return data;
      } else {
        throw ClientError(
          message: 'Failed to create engine session',
          statusCode: response.statusCode,
          details: response.body,
        );
      }
    } catch (e) {
      _logger.e('Error creating engine session', error: e);
      if (e is ClientError) rethrow;
      throw ClientError(
        message: 'Failed to create engine session: ${e.toString()}',
      );
    }
  }

  Future<String> getSessionToken({required String apiKey}) async {
    final url = Uri.parse('$baseUrl$version/auth/session-token');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
          ...Constants.clientMetadata,
        },
      );

      if (response.statusCode != 200) {
        _logger.e('Session token request failed', error: {
          'statusCode': response.statusCode,
          'body': response.body,
          'url': url.toString(),
        });
        throw ClientError(
          message: 'Failed to get session token',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final data = jsonDecode(response.body);
      final token = data['sessionToken'];

      if (token == null || token.isEmpty) {
        throw ClientError(message: 'Invalid session token received');
      }

      return token;
    } catch (e) {
      _logger.e('Error getting session token', error: e);
      if (e is ClientError) rethrow;
      throw ClientError(
        message: 'Failed to get session token: ${e.toString()}',
      );
    }
  }

  bool isTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (e) {
      _logger.w('Failed to decode JWT token', error: e);
      return true;
    }
  }

  Future<Map<String, dynamic>> createSessionWithProxy({
    required String serverUrl,
    required String personaId,
    bool disableBrains = false,
    Map<String, dynamic>? webrtcOffer,
    List<Map<String, dynamic>>? clientIceCandidates,
  }) async {
    try {
      final url = Uri.parse('$serverUrl/v1/engine/session-with-proxy');
      _logger.d('Creating session with proxy at: $url');

      final requestBody = {
        'personaId': personaId,
        'disableBrains': disableBrains,
      };

      if (webrtcOffer != null) {
        requestBody['webrtcOffer'] = webrtcOffer;
      }

      if (clientIceCandidates != null) {
        requestBody['clientIceCandidates'] = clientIceCandidates;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw ClientError(
          message: 'Failed to create session with proxy',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      return jsonDecode(response.body);
    } catch (e) {
      _logger.e('Error creating session with proxy', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> negotiateSession({
    required String serverUrl,
    required Map<String, dynamic> webrtcOffer,
    required List<Map<String, dynamic>> clientIceCandidates,
  }) async {
    try {
      final url = Uri.parse('$serverUrl/v1/engine/session');
      _logger.d('Negotiating session at: $url');

      final requestBody = {
        'webrtcOffer': webrtcOffer,
        'clientIceCandidates': clientIceCandidates,
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw ClientError(
          message: 'Failed to negotiate session',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      return jsonDecode(response.body);
    } catch (e) {
      _logger.e('Error negotiating session', error: e);
      rethrow;
    }
  }
}
