import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

import '../events/anam_event.dart';
import '../events/event_emitter.dart';
import '../utils/client_error.dart';

class StreamingClient {
  final EventEmitter eventEmitter;
  final Logger _logger;
  final List<Map<String, dynamic>>? iceServers;
  final bool disableClientAudio;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  RTCRtpTransceiver? videoTransceiver;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isConnected = false;
  bool _inputAudioEnabled = true;

  StreamingClient({
    required this.eventEmitter,
    this.iceServers,
    this.disableClientAudio = false,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  Future<void> initializePeerConnection() async {
    final configuration = {
      'iceServers': iceServers ??
          [
            {'urls': 'stun:stun.l.google.com:19302'},
          ],
    };

    _logger.d('🧊 ICE Servers used: ${configuration['iceServers']}');
    try {
      // Create PeerConnection with no legacy constraints
      _peerConnection = await createPeerConnection(configuration);

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        eventEmitter.emit(AnamEvent.iceConnectionStateChanged, {
          'candidate': candidate.toMap(),
        });
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        _logger.d('🔌 WebRTC Connection state changed: $state');

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _isConnected = true;
          _logger.d('✅ WebRTC Connected!');

          eventEmitter.emit(AnamEvent.connectionEstablished);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          // Transient: ICE lost connectivity but may recover. Trigger an ICE
          // restart and wait — do NOT emit connectionClosed here.
          _isConnected = false;
          _logger.d('⚠️ WebRTC Disconnected (transient) — restarting ICE');
          _peerConnection?.restartIce();
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _isConnected = false;
          _logger.d('❌ WebRTC Failed/Closed');
          eventEmitter.emit(AnamEvent.connectionClosed);
        }
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        _logger.d('🧊 ICE Connection state: $state');
      };

      _peerConnection!.onSignalingState = (RTCSignalingState state) {
        _logger.d('📡 Signaling state: $state');
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
          if (event.track.kind == 'video') {
            eventEmitter.emit(AnamEvent.videoStreamStarted, _remoteStream);
          } else if (event.track.kind == 'audio') {
            eventEmitter.emit(AnamEvent.audioStreamStarted, _remoteStream);
          }
        }
      };

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        _setupDataChannel(channel);
      };

      // 1. Setup Media Sections FIRST
      // Order matters for some servers: Audio then Video is a common pattern.

      // Audio: SendRecv if mic is enabled, else RecvOnly
      if (!disableClientAudio) {
        await _setupLocalStream();
        _logger.d('🔊 Local audio setup complete');
      } else {
        await _peerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        _logger.d('🔊 Added audio transceiver (recvonly)');
      }

      // Video: Always RecvOnly (Persona -> Client)
      videoTransceiver = await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      _logger.d('📹 Added video transceiver (recvonly)');

      // 2. Data Channel - Listen for server-created channel only
      // Most servers manage the data channel themselves.
      _logger.d('📡 Waiting for server to open data channel...');
    } catch (e) {
      _logger.e('Failed to initialize peer connection', error: e);
      throw ClientError(
        message: 'Failed to initialize peer connection: ${e.toString()}',
      );
    }
  }

  Future<void> _setupLocalStream() async {
    if (disableClientAudio) {
      _logger.d('Client audio disabled - skipping local stream setup');
      return;
    }

    try {
      final mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _logger.d('Local stream setup complete');
    } catch (e) {
      _logger.e('Failed to setup local stream', error: e);
      throw ClientError(
        message: 'Failed to access microphone: ${e.toString()}',
      );
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    _logger.d('📊 Setting up data channel: ${channel.label}');

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      try {
        final data = jsonDecode(message.text);
        _logger.d('💬 Data channel message received: $data');

        eventEmitter.emit(AnamEvent.dataChannelMessage, data);

        if (data['type'] == 'persona_talking') {
          eventEmitter.emit(AnamEvent.personaTalking);
        } else if (data['type'] == 'persona_listening') {
          eventEmitter.emit(AnamEvent.personaListening);
        }
      } catch (e) {
        _logger.e('Failed to parse data channel message', error: e);
      }
    };

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      _logger.d('📊 Data channel state changed: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _logger.d('✅ Data channel opened!');
      }
    };
  }

  Future<Map<String, dynamic>> createOffer() async {
    try {
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        _logger.d('🧊 ICE gathering state: $state');
      };

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _logger.d(
          '📋 Created offer (trickle ICE — candidates will be sent separately)');

      return {
        'type': offer.type,
        'sdp': offer.sdp,
      };
    } catch (e) {
      _logger.e('Failed to create offer', error: e);
      throw ClientError(
        message: 'Failed to create offer: ${e.toString()}',
      );
    }
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> answer) async {
    try {
      final description = RTCSessionDescription(
        answer['sdp'],
        answer['type'],
      );

      await _peerConnection!.setRemoteDescription(description);
      _logger.d('Remote answer set successfully');
    } catch (e) {
      _logger.e('Failed to set remote answer', error: e);
      throw ClientError(
        message: 'Failed to set remote answer: ${e.toString()}',
      );
    }
  }

  Future<void> addIceCandidate(dynamic rawCandidate) async {
    try {
      // Some servers nest the candidate inside a 'candidate' key; others send
      // it flat. Handle both shapes.
      final Map<String, dynamic> candidate;
      if (rawCandidate is Map) {
        final raw = Map<String, dynamic>.from(rawCandidate);
        if (raw['candidate'] is Map) {
          candidate = Map<String, dynamic>.from(raw['candidate'] as Map);
        } else {
          candidate = raw;
        }
      } else {
        _logger.w(
            'Skipping ICE candidate — unexpected type: ${rawCandidate.runtimeType}');
        return;
      }

      // sdpMLineIndex may arrive as a String from some servers.
      final mLineIndex = candidate['sdpMLineIndex'] is int
          ? candidate['sdpMLineIndex'] as int
          : int.tryParse(candidate['sdpMLineIndex']?.toString() ?? '') ?? 0;

      final iceCandidate = RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        mLineIndex,
      );

      await _peerConnection!.addCandidate(iceCandidate);
      _logger.d('ICE candidate added successfully');
    } catch (e) {
      _logger.e('Failed to add ICE candidate', error: e);
    }
  }

  void sendMessage(String message) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(message));
      _logger.d('Message sent via data channel: $message');
    } else {
      _logger.w('Cannot send message - data channel not ready');
    }
  }

  void setInputAudioEnabled(bool enabled) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = enabled;
      });

      _inputAudioEnabled = enabled;
      eventEmitter.emit(
        enabled ? AnamEvent.inputAudioEnabled : AnamEvent.inputAudioDisabled,
      );

      _logger.d('Input audio ${enabled ? "enabled" : "disabled"}');
    }
  }

  bool get isConnected => _isConnected;
  bool get isDataChannelOpen =>
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get inputAudioEnabled => _inputAudioEnabled;
  MediaStream? get remoteStream => _remoteStream;
  RTCPeerConnection? get peerConnection => _peerConnection;

  Future<void> close() async {
    try {
      _dataChannel?.close();
      _dataChannel = null;

      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_remoteStream != null) {
        _remoteStream!.getTracks().forEach((track) {
          track.stop();
        });
        await _remoteStream!.dispose();
        _remoteStream = null;
      }

      await _peerConnection?.close();
      _peerConnection = null;

      _isConnected = false;
      _logger.d('Streaming client closed');
    } catch (e) {
      _logger.e('Error closing streaming client', error: e);
    }
  }
}
