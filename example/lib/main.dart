import 'package:flutter/material.dart';
import 'package:flutter_anam_sdk/flutter_anam_sdk.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anam Avatar Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AnamAvatarDemo(),
    );
  }
}

class AnamAvatarDemo extends StatefulWidget {
  const AnamAvatarDemo({super.key});

  @override
  State<AnamAvatarDemo> createState() => _AnamAvatarDemoState();
}

class _AnamAvatarDemoState extends State<AnamAvatarDemo> {
  AnamClient? _anamClient;
  RTCVideoRenderer? _remoteRenderer;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _sessionTokenController = TextEditingController();

  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isMicEnabled = true;
  List<Message> _messages = [];
  String _connectionStatus = 'Disconnected';
  bool _isVideoStreamReady = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
  }

  Future<void> _initializeRenderer() async {
    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer!.initialize();
    setState(() {});
  }

  @override
  void dispose() {
    _messageController.dispose();
    _sessionTokenController.dispose();
    _remoteRenderer?.dispose();
    _anamClient?.dispose();
    super.dispose();
  }

  Future<void> _connectToAvatar() async {
    if (_sessionTokenController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your session token')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Creating client...';
    });

    try {
      // Create AnamClient with session token - direct connection
      _anamClient = AnamClientFactory.createClient(
        sessionToken: _sessionTokenController.text,
        enableLogging: true,
      );

      // Setup event listeners
      _anamClient!
          .on<List<Message>>(AnamEvent.messageHistoryUpdated)
          .listen((messages) {
        setState(() {
          _messages = messages;
        });
      });

      _anamClient!.on(AnamEvent.connectionClosed).listen((_) {
        setState(() {
          _isConnected = false;
          _connectionStatus = 'Disconnected';
        });
      });

      _anamClient!.on(AnamEvent.connectionEstablished).listen((_) {
        setState(() {
          _connectionStatus = 'WebRTC Connected';
        });
      });

      _anamClient!.on(AnamEvent.videoStreamStarted).listen((_) {
        setState(() {
          _isVideoStreamReady = true;
          _connectionStatus = 'Video Stream Active';
        });
      });

      _anamClient!.on(AnamEvent.sessionReady).listen((_) {
        setState(() {
          _connectionStatus = 'Session Ready';
        });
      });

      _anamClient!.on(AnamEvent.error).listen((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $error')),
          );
        }
      });

      setState(() {
        _connectionStatus = 'Starting session...';
      });

      // Direct connection using talk method
      await _anamClient!.talk(
        onStreamReady: (stream) {
          if (stream != null && _remoteRenderer != null) {
            _remoteRenderer!.srcObject = stream;
            setState(() {
              _isConnected = true;
              _isConnecting = false;
              _connectionStatus = 'Connected';
              _isVideoStreamReady = true;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Failed to connect';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }

  void _disconnect() {
    _anamClient?.stopStreaming();
    setState(() {
      _isConnected = false;
      _isVideoStreamReady = false;
      _connectionStatus = 'Disconnected';
      _messages.clear();
    });
  }

  void _sendMessage() {
    if (_messageController.text.isEmpty || !_isConnected) return;

    _anamClient?.sendUserMessage(_messageController.text);
    _messageController.clear();
  }

  void _toggleMic() {
    setState(() {
      _isMicEnabled = !_isMicEnabled;
    });

    if (_isMicEnabled) {
      _anamClient?.unmuteInputAudio();
    } else {
      _anamClient?.muteInputAudio();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Anam Avatar Demo - Direct Connection'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isConnected) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _sessionTokenController,
                    decoration: const InputDecoration(
                      labelText: 'Session Token',
                      hintText: 'Enter your Anam session token',
                      border: OutlineInputBorder(),
                      helperText:
                          'You need to generate a session token using the Anam API',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isConnecting ? null : _connectToAvatar,
                    child: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect to Avatar'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Video section
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'Status: $_connectionStatus',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isVideoStreamReady ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: AnamAvatarView(
                      renderer: _remoteRenderer,
                      onMicToggle: _toggleMic,
                      isMicEnabled: _isMicEnabled,
                    ),
                  ),
                ),
              ],
            ),
            // Messages list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message.role == MessageRole.user;
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Input field
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
