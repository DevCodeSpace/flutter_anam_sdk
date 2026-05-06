import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/client_error.dart';
import '../utils/constants.dart';

enum SignalingMessageType {
  offer,
  answer,
  iceCandidate,
  heartbeat,
  error,
  close,
}

class SignalingClient {
  final String sessionId;
  final String sessionToken;
  final String engineHost;
  final String engineProtocol;
  final String signallingEndpoint;
  final String? proxyUrl;
  final Logger _logger;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  SignalingClient({
    required String sessionId,
    required this.sessionToken,
    required this.engineHost,
    required this.engineProtocol,
    required this.signallingEndpoint,
    this.proxyUrl,
    Logger? logger,
  })  : sessionId = sessionId.trim().replaceAll(RegExp(r'#$'), ''),
        _logger = logger ?? Logger();

  Future<void> connect() async {
    try {
      String wsUrl;

      if (proxyUrl != null) {
        // Use proxy URL if provided
        var baseUri = Uri.parse(proxyUrl!);
        final queryParams = Map<String, String>.from(baseUri.queryParameters);
        queryParams['engineHost'] = engineHost;
        queryParams['engineProtocol'] = engineProtocol;
        queryParams['signallingEndpoint'] = signallingEndpoint;
        queryParams['session_id'] = sessionId;

        wsUrl = baseUri.replace(queryParameters: queryParams).toString();
        log('Using proxy WebSocket connection');
      } else {
        // Construct WebSocket URL direct
        final wsProtocol = engineProtocol == 'https' ? 'wss' : 'ws';

        // Extract host; strip port if zero or invalid (Dart Uri() leaves port as
        // 0 for unknown schemes like wss, which web_socket_channel then passes
        // Use standard URI parsing for robustness
        final hostUri = Uri.parse(
            engineHost.contains('://') ? engineHost : 'https://$engineHost');
        final baseHost = hostUri.host;
        final basePort = hostUri.port;

        final endpointPath = signallingEndpoint.startsWith('/')
            ? signallingEndpoint
            : '/$signallingEndpoint';

        wsUrl = Uri(
          scheme: wsProtocol,
          host: baseHost,
          port: basePort > 0 ? basePort : null,
          path: endpointPath,
          queryParameters: {'session_id': sessionId},
        ).toString();
      }

      log('Attempting WebSocket connection to: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _startHeartbeat();

      log('WebSocket connection opened');
    } catch (e) {
      log('Failed to connect to signaling server: $e');
      throw ClientError(
        message: 'Failed to connect to signaling server: ${e.toString()}',
      );
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final decoded = jsonDecode(data);

      if (decoded is! Map<String, dynamic>) {
        log('Ignoring non-object signaling message (${decoded.runtimeType})');
        return;
      }

      final message = decoded;

      // Handle different message formats based on what we receive
      final messageType = message['type'] ?? message['actionType'];
      log('Received signaling message: $messageType');
      log('Full message: $message');

      if (messageType == 'heartbeat') {
        _sendHeartbeatResponse();
      } else if (messageType == 'warning') {
        final payload = message['payload'];
        _logger.w('⚠️ Signaling warning: $payload');
        _messageController.add({
          'type': 'warning',
          'data': payload,
        });
      } else if (messageType == 'endsession') {
        final rawPayload = message['payload'];
        final reason = (rawPayload is Map ? rawPayload['reason'] : null) ??
            message['reason'] ??
            'No reason provided';
        _logger.w(
            '⚠️ Session ended by server: ${message['sessionId']}. Reason: $reason');
        _logger.d('📦 Full termination message: $message');

        _isConnected = false;
        _stopHeartbeat();

        _messageController.addError(ClientError(
          message: 'Session ended by server: $reason',
        ));
        return;
      } else if (messageType == 'answer') {
        // The JS SDK receives answer with payload.connectionDescription
        final payload = message['payload'];
        if (payload != null &&
            payload is Map &&
            payload['connectionDescription'] != null) {
          _messageController.add({
            'type': 'answer',
            'data': Map<String, dynamic>.from(
                payload['connectionDescription'] as Map),
          });
        } else {
          // Fallback for other formats
          final answerData = message['data'] ?? message['payload'] ?? message;
          _messageController.add({
            'type': 'answer',
            'data': answerData,
          });
        }
      } else if (messageType == 'icecandidate') {
        // Forward ICE candidates with consistent format
        _messageController.add({
          'type': 'ice_candidate',
          'data': message['payload'],
        });
      } else if (messageType == 'registered') {
        _logger.d('✅ Successfully registered with signaling server');
        _messageController.add({'type': 'registered'});
      } else {
        _messageController.add(message);
      }
    } catch (e) {
      _logger.e('Failed to parse signaling message', error: e);
    }
  }

  void _handleError(dynamic error) {
    _logger.e('WebSocket error', error: error);
    _messageController.addError(ClientError(
      message: 'WebSocket error: ${error.toString()}',
    ));
  }

  void _handleDisconnect() {
    _logger.d('Disconnected from signaling server');
    _isConnected = false;
    _stopHeartbeat();

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(milliseconds: 100 * _reconnectAttempts);
      _logger.i(
          'Attempting to reconnect in ${delay.inMilliseconds}ms (Attempt $_reconnectAttempts/$_maxReconnectAttempts)');
      Timer(delay, () => connect());
    } else {
      _logger.e('Max reconnect attempts reached');
      if (!_messageController.isClosed) {
        _messageController.add({'type': 'signaling_closed'});
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Constants.heartbeatInterval, (_) {
      if (_isConnected) {
        sendMessage({
          'type': 'heartbeat',
          'actionType': 'heartbeat',
          'sessionId': sessionId,
        });
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeatResponse() {
    _logger.d('💓 Received heartbeat, sending response');
    sendMessage({
      'type': 'heartbeat',
      'actionType': 'heartbeat',
      'sessionId': sessionId,
    });
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      final jsonMessage = jsonEncode(message);
      (_channel!.sink as dynamic).add(jsonMessage);
    } else {
      log('Cannot send message: Not connected');
    }
  }

  void sendOffer(Map<String, dynamic> offer) {
    // Match JS SDK format exactly
    sendMessage({
      'actionType': 'offer',
      'sessionId': sessionId,
      'payload': {
        'connectionDescription': offer,
        'userUid': sessionId,
      },
    });
  }

  void sendRegister() {
    sendMessage({
      'type': 'register',
      'actionType': 'register',
      'sessionId': sessionId,
      'sessionToken': sessionToken, // Top-level
      'payload': {
        'token': sessionToken, // And in payload just in case
      },
    });
  }

  void sendIceCandidate(dynamic candidate) {
    final payload =
        candidate is RTCIceCandidate ? candidate.toMap() : candidate;
    sendMessage({
      'type': 'icecandidate',
      'actionType': 'icecandidate',
      'sessionId': sessionId,
      'payload': payload,
    });
  }

  bool get isConnected => _isConnected;

  Future<void> close() async {
    _stopHeartbeat();
    _subscription?.cancel();
    await _channel?.sink.close();
    await _messageController.close();
    _isConnected = false;
    _logger.d('Signaling client closed');
  }
}
