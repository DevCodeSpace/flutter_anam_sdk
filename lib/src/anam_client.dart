import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import 'api/core_api_client.dart';
import 'events/anam_event.dart';
import 'events/event_emitter.dart';
import 'models/anam_client_options.dart';
import 'models/message.dart';
import 'models/persona_config.dart';
import 'streaming/signaling_client.dart';
import 'streaming/streaming_client.dart';
import 'utils/client_error.dart';

class AnamClient {
  final AnamClientOptions options;
  final Logger _logger;
  final EventEmitter _eventEmitter = EventEmitter();
  final List<Message> _messageHistory = [];
  final _uuid = const Uuid();

  late CoreApiClient _apiClient;
  StreamingClient? _streamingClient;
  SignalingClient? _signalingClient;

  String? _currentSessionId;
  PersonaConfig? _currentPersona;
  bool _isSessionActive = false;
  int _agentAudioSequenceNumber = 0;

  AnamClient({
    required this.options,
    Logger? logger,
  }) : _logger = logger ??
            Logger(
              printer: PrettyPrinter(),
              level: options.enableLogging ? Level.debug : Level.warning,
            ) {
    _apiClient = CoreApiClient(
      baseUrl: options.apiBaseUrl,
      version: options.apiVersion,
      apiKey: options.apiKey,
      sessionToken: options.sessionToken,
      disableBrains: options.disableBrains,
      logger: _logger,
    );
  }

  Future<void> _ensureSessionToken() async {
    if (options.sessionToken == null && options.apiKey != null) {
      try {
        final sessionToken =
            await _apiClient.getSessionToken(apiKey: options.apiKey!);
        // Update the API client with the session token
        _apiClient = CoreApiClient(
          baseUrl: options.apiBaseUrl,
          version: options.apiVersion,
          sessionToken: sessionToken,
          disableBrains: options.disableBrains,
          logger: _logger,
        );
        _logger.d('Session token obtained successfully');
      } catch (e) {
        _logger.e('Failed to get session token', error: e);
        rethrow;
      }
    }
  }

  Stream<T> on<T>(AnamEvent event) => _eventEmitter.on<T>(event);

  Future<void> talk({
    PersonaConfig? personaConfig,
    required Function(MediaStream?) onStreamReady,
    Map<String, dynamic>? preNegotiatedSession,
    String? proxyUrl,
  }) async {
    if (_isSessionActive) {
      throw ClientError(message: 'A session is already active');
    }

    try {
      _isSessionActive = true;

      // Check if we have session data from server (proxy mode)
      if (preNegotiatedSession != null) {
        // Extract session data
        _currentSessionId = preNegotiatedSession['sessionId'];
        final sessionToken = preNegotiatedSession['sessionToken'];
        final engineHost = preNegotiatedSession['engineHost'];
        final engineProtocol =
            preNegotiatedSession['engineProtocol'] ?? 'https';
        final signallingEndpoint = preNegotiatedSession['signallingEndpoint'];
        final clientConfig = preNegotiatedSession['clientConfig'] ?? {};

        _logger.d('Using server-created session: $_currentSessionId');

        // Initialize streaming client with ICE servers
        _streamingClient = StreamingClient(
          eventEmitter: _eventEmitter,
          logger: _logger,
          disableClientAudio: options.disableClientAudio,
          iceServers: (clientConfig['iceServers'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList(),
        );

        // Initialize signaling client - use proxy if provided
        _signalingClient = SignalingClient(
          sessionId: _currentSessionId!,
          sessionToken: sessionToken,
          engineHost: engineHost,
          engineProtocol: engineProtocol,
          signallingEndpoint: signallingEndpoint,
          proxyUrl: proxyUrl,
          logger: _logger,
        );

        // ✅ Register handlers BEFORE initializing/connecting
        _setupSignalingHandlers();
        _setupStreamingHandlers(onStreamReady);

        // Run peer connection setup and WebSocket connect in parallel
        await Future.wait([
          _streamingClient!.initializePeerConnection(),
          _signalingClient!.connect(),
        ]);

        final offer = await _streamingClient!.createOffer();
        _signalingClient!.sendOffer(offer);

        _eventEmitter.emit(AnamEvent.sessionReady, {
          'sessionId': _currentSessionId,
        });

        return;
      }

      // Original flow - handle everything client-side
      // Use provided persona config or default from options
      final config = personaConfig ?? options.defaultPersonaConfig;
      if (config == null) {
        throw ClientError(message: 'No persona configuration provided');
      }

      // Ensure we have a session token if using API key
      await _ensureSessionToken();

      _currentPersona = config;

      // Use the existing session token
      final sessionToken = options.sessionToken ?? _apiClient.sessionToken;

      if (sessionToken == null) {
        throw ClientError(message: 'No session token available');
      }

      // Create engine session with Anam API
      _logger.d('Creating engine session...');
      final sessionData = await _apiClient.startSession(
        personaConfig: config,
      );

      _currentSessionId = sessionData['sessionId'];
      final engineHost = sessionData['engineHost'];
      final engineProtocol = sessionData['engineProtocol'] ?? 'https';
      final signallingEndpoint = sessionData['signallingEndpoint'];
      final clientConfig = sessionData['clientConfig'] ?? {};

      _logger.d('Session created: $_currentSessionId');
      _logger.d('Engine host: $engineHost');
      _logger.d('Signalling endpoint: $signallingEndpoint');

      _streamingClient = StreamingClient(
        eventEmitter: _eventEmitter,
        logger: _logger,
        disableClientAudio: options.disableClientAudio,
        iceServers: (clientConfig['iceServers'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList(),
      );

      _signalingClient = SignalingClient(
        sessionId: _currentSessionId!,
        sessionToken: sessionToken,
        engineHost: engineHost,
        engineProtocol: engineProtocol,
        signallingEndpoint: signallingEndpoint,
        logger: _logger,
      );

      // ✅ Register handlers BEFORE initializing/connecting
      _setupSignalingHandlers();
      _setupStreamingHandlers(onStreamReady);

      // Run peer connection setup and WebSocket connect in parallel
      await Future.wait([
        _streamingClient!.initializePeerConnection(),
        _signalingClient!.connect(),
      ]);

      // ✅ Register immediately after connecting
      _signalingClient!.sendRegister();

      // ✅ Wait for 'registered' acknowledgment before sending offer
      try {
        await _signalingClient!.messages
            .firstWhere(
                (msg) => (msg['type'] ?? msg['actionType']) == 'registered')
            .timeout(const Duration(milliseconds: 1500));
        _logger.d('✅ Registration confirmed by server');
      } catch (e) {
        _logger.w(
            '⚠️ Registration acknowledgment timed out or failed — proceeding anyway');
      }

      final offer = await _streamingClient!.createOffer();
      _signalingClient!.sendOffer(offer);

      _eventEmitter.emit(AnamEvent.sessionReady, {
        'sessionId': _currentSessionId,
        'persona': config.toJson(),
      });
    } catch (e) {
      _isSessionActive = false;
      _logger.e('Failed to start talk session', error: e);
      _eventEmitter.emit(AnamEvent.error, e);
      await stopStreaming('Failed to start session: $e');
      rethrow;
    }
  }

  void _setupSignalingHandlers() {
    _signalingClient!.messages.listen((message) async {
      try {
        _logger.d(
            '🎯 Handling signaling message: ${message['type'] ?? message['actionType']}');

        final messageType = message['type'] ?? message['actionType'];
        switch (messageType) {
          case 'answer':
            _logger.d('📨 Received answer!');
            _logger.d('📄 Answer SDP: ${message['data']?['sdp']}');
            await _streamingClient!.setRemoteAnswer(message['data']);
            break;
          case 'ice_candidate':
          case 'icecandidate':
            _logger.d('🧊 Received ICE candidate');
            await _streamingClient!.addIceCandidate(message['data']);
            break;
          case 'error':
            _logger.e('Signaling error: ${message['data']}');
            _eventEmitter.emit(
                AnamEvent.error,
                ClientError(
                  message: 'Signaling error',
                  details: message['data'],
                ));
            break;
          case 'sessionready':
            _logger.d('📢 Session ready received');
            // The JS SDK emits this event when session is ready
            _eventEmitter.emit(AnamEvent.sessionReady, messageType);
            break;
          case 'warning':
            _eventEmitter.emit(AnamEvent.warning, message['data']);
            break;
          case 'signaling_closed':
            // Normal: Anam's server closes the WebSocket once ICE signaling is
            // complete. WebRTC stays alive independently — no action needed.
            _logger.d(
                '📡 Signaling WebSocket closed (expected after ICE exchange)');
            break;
          default:
            _logger.w('Unknown signaling message type: $messageType');
        }
      } catch (e) {
        _logger.e('Error handling signaling message', error: e);
      }
    }, onError: (error) {
      _logger.e('Signaling stream error', error: error);
      _eventEmitter.emit(AnamEvent.error, error);

      // If session was ended by server, we should stop streaming
      if (error is ClientError &&
          error.message.contains('Session ended by server')) {
        stopStreaming('Session ended by server');
      }
    });
  }

  void _setupStreamingHandlers(Function(MediaStream?) onStreamReady) {
    _streamingClient!.eventEmitter
        .on<dynamic>(AnamEvent.videoStreamStarted)
        .listen((stream) {
      _logger.d('🎬 Video stream started event received');
      onStreamReady(stream as MediaStream?);
    });

    _streamingClient!.eventEmitter
        .on<dynamic>(AnamEvent.iceConnectionStateChanged)
        .listen((data) {
      if (data != null && data is Map && data['candidate'] != null) {
        _signalingClient!.sendIceCandidate(data['candidate']);
      }
    });

    _streamingClient!.eventEmitter
        .on<dynamic>(AnamEvent.dataChannelMessage)
        .listen((data) {
      if (data['type'] == 'message') {
        final message = Message(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: data['content'] ?? '',
          timestamp: DateTime.now(),
        );
        _addToMessageHistory(message);
      }
    });
  }

  void sendUserMessage(String content) {
    if (!_isSessionActive || _signalingClient == null) {
      throw ClientError(message: 'No active session');
    }

    final message = Message(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );

    _addToMessageHistory(message);

    // Send through WebSocket (signaling client) instead of data channel
    _signalingClient!.sendMessage({
      'type': 'user_message',
      'content': content,
    });
  }

  void interruptPersona() {
    if (!_isSessionActive || _streamingClient == null) {
      throw ClientError(message: 'No active session');
    }

    _streamingClient!.sendMessage(jsonEncode({
      'type': 'interrupt',
    }));
  }

  /// Send audio bytes for lip-sync (Brain-less mode)
  /// Matches Anam JS SDK AgentAudioInputStream.sendAudioChunk
  void appendInputAudio(Uint8List bytes) {
    if (!_isSessionActive || _signalingClient == null) return;

    _signalingClient!.sendMessage({
      'actionType': 'agentaudioinput',
      'sessionId': _currentSessionId,
      'payload': {
        'audioData': base64Encode(bytes),
        'encoding': 'pcm_s16le',
        'sampleRate': 24000,
        'channels': 1,
        'sequenceNumber': _agentAudioSequenceNumber++,
      },
    });
  }

  /// Signal end of the current audio sequence/turn.
  /// Matches Anam JS SDK AgentAudioInputStream.endSequence
  void endAgentAudioSequence() {
    if (!_isSessionActive || _signalingClient == null) return;

    _signalingClient!.sendMessage({
      'actionType': 'agentaudioinputend',
      'sessionId': _currentSessionId,
      'payload': {},
    });
    _agentAudioSequenceNumber = 0;
  }

  void setInputAudioEnabled(bool enabled) {
    if (_streamingClient != null) {
      _streamingClient!.setInputAudioEnabled(enabled);
    }
  }

  void muteInputAudio() {
    setInputAudioEnabled(false);
  }

  void unmuteInputAudio() {
    setInputAudioEnabled(true);
  }

  void streamToVideoElement(RTCVideoRenderer videoRenderer) {
    if (_streamingClient != null && _streamingClient!.remoteStream != null) {
      videoRenderer.srcObject = _streamingClient!.remoteStream;
    }
  }

  void _addToMessageHistory(Message message) {
    _messageHistory.add(message);
    _eventEmitter.emit(AnamEvent.messageHistoryUpdated, _messageHistory);
  }

  List<Message> get messageHistory => List.unmodifiable(_messageHistory);
  bool get isSessionActive => _isSessionActive;
  bool get isConnected => _streamingClient?.isConnected ?? false;
  bool get isDataChannelOpen => _streamingClient?.isDataChannelOpen ?? false;
  bool get inputAudioEnabled => _streamingClient?.inputAudioEnabled ?? false;
  PersonaConfig? get currentPersona => _currentPersona;
  String? get currentSessionId => _currentSessionId;

  Future<void> stopStreaming([String reason = 'Requested by user']) async {
    if (!_isSessionActive) return;

    _logger.i('🛑 Stopping streaming session. Reason: $reason');
    _isSessionActive = false;
    _currentSessionId = null;
    _currentPersona = null;

    await _streamingClient?.close();
    await _signalingClient?.close();

    _streamingClient = null;
    _signalingClient = null;

    _eventEmitter.emit(AnamEvent.connectionClosed);
    _logger.d('Streaming stopped');
  }

  void dispose() {
    stopStreaming('Client disposed');
    _eventEmitter.dispose();
  }
}

class AnamClientFactory {
  static AnamClient createClient({
    required String sessionToken,
    bool enableLogging = false,
    bool disableClientAudio = false,
  }) {
    return AnamClient(
      options: AnamClientOptions(
        sessionToken: sessionToken,
        enableLogging: enableLogging,
        disableClientAudio: disableClientAudio,
      ),
    );
  }

  /// Create a WebRTC offer without requiring a full client instance
  /// This is useful for server-side negotiation where we need an offer
  /// before we have a session token
  static Future<Map<String, dynamic>> createWebRTCOffer({
    List<Map<String, dynamic>>? iceServers,
    bool disableClientAudio = false,
    Logger? logger,
  }) async {
    final tempLogger = logger ?? Logger(level: Level.warning);
    final tempEventEmitter = EventEmitter();

    // Create a temporary streaming client just for offer generation
    final tempClient = StreamingClient(
      eventEmitter: tempEventEmitter,
      logger: tempLogger,
      disableClientAudio: disableClientAudio,
      iceServers: iceServers,
    );

    try {
      await tempClient.initializePeerConnection();
      final offer = await tempClient.createOffer();

      // Collect ICE candidates
      final iceCandidates = <Map<String, dynamic>>[];
      final sub = tempEventEmitter
          .on<dynamic>(AnamEvent.iceConnectionStateChanged)
          .listen((data) {
        if (data != null && data['candidate'] != null) {
          iceCandidates.add(data['candidate']);
        }
      });

      // Wait for ICE gathering
      await Future.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      return {
        'offer': offer,
        'iceCandidates': iceCandidates,
      };
    } finally {
      await tempClient.close();
      tempEventEmitter.dispose();
    }
  }

  static AnamClient createClientWithOptions({
    required String sessionToken,
    required String personaId,
    bool enableLogging = false,
    bool disableBrains = false,
    String? name,
    String? avatarId,
    String? voiceId,
    String? llmId,
    String? systemPrompt,
    int? maxSessionLengthSeconds,
    String? languageCode,
  }) {
    return AnamClient(
      options: AnamClientOptions(
        sessionToken: sessionToken,
        enableLogging: enableLogging,
        defaultPersonaConfig: PersonaConfig(
          personaId: personaId,
          name: name ?? 'Avatar',
          avatarId: avatarId ?? 'default_avatar',
          voiceId: voiceId ?? 'default_voice',
          llmId: llmId,
          systemPrompt: systemPrompt,
          maxSessionLengthSeconds: maxSessionLengthSeconds,
          languageCode: languageCode,
        ),
        disableBrains: disableBrains,
      ),
    );
  }

  static AnamClient unsafeCreateClientWithApiKey({
    required String apiKey,
    bool enableLogging = false,
  }) {
    return AnamClient(
      options: AnamClientOptions(
        apiKey: apiKey,
        enableLogging: enableLogging,
      ),
    );
  }
}
