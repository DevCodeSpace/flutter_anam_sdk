# Flutter Anam SDK

A Flutter package for integrating [Anam AI](https://anam.ai)'s real-time avatar system into your Flutter applications. Built on WebRTC, this is a Flutter port of the [Anam JavaScript SDK](https://github.com/anam-org/javascript-sdk).

<img src="https://raw.githubusercontent.com/DevCodeSpace/flutter_anam_sdk/main/screenshots/banner.png" width="100%"/>

## Features

- Real-time avatar video/audio streaming via WebRTC
- Two-way audio communication with microphone controls
- Text messaging with full message history
- Event-driven architecture for reactive UIs
- Custom persona configuration (avatar, voice, system prompt, language)
- Server-side session management with WebSocket proxy support
- Custom audio mode for bring-your-own-transcription pipelines
- Built-in `AnamAvatarView` widget
- Cross-platform: iOS, Android, macOS, Web

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_anam_sdk: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Platform Setup

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice communication with the avatar</string>
<key>NSCameraUsageDescription</key>
<string>Required for video communication with the avatar</string>
```

### macOS

1. Add to `macos/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Required for voice communication with the avatar</string>
<key>NSCameraUsageDescription</key>
<string>Required for video communication with the avatar</string>
```

2. Add to both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CAMERA" />
```

## Quick Start

### 1. Create a client

**Production (session token from your server):**

```dart
import 'package:flutter_anam_sdk/flutter_anam_sdk.dart';

final client = AnamClientFactory.createClient(
  sessionToken: 'your-session-token',
);
```

**Development only (direct API key — never ship to production):**

```dart
final client = AnamClientFactory.unsafeCreateClientWithApiKey(
  apiKey: 'your-api-key',
  enableLogging: true,
);
```

### 2. Set up a video renderer

```dart
import 'package:flutter_webrtc/flutter_webrtc.dart';

final renderer = RTCVideoRenderer();
await renderer.initialize();
```

### 3. Start a session

```dart
final personaConfig = PersonaConfig(
  personaId: 'your-persona-id',
  name: 'AI Assistant',
  avatarId: 'default_avatar',
  voiceId: 'default_voice',
  systemPrompt: 'You are a helpful assistant.',
);

await client.talk(
  personaConfig: personaConfig,
  onStreamReady: (stream) {
    if (stream != null) {
      renderer.srcObject = stream;
    }
  },
);
```

### 4. Display the avatar

```dart
AnamAvatarView(
  renderer: renderer,
  onMicToggle: () => client.setInputAudioEnabled(!client.inputAudioEnabled),
  isMicEnabled: client.inputAudioEnabled,
)
```

### 5. Send messages and control the session

```dart
// Send a text message
client.sendUserMessage('Hello!');

// Interrupt the avatar while it speaks
client.interruptPersona();

// Mute / unmute microphone
client.muteInputAudio();
client.unmuteInputAudio();

// End the session
await client.stopStreaming();

// Clean up when done
client.dispose();
```

## Event Handling

Subscribe to events with `client.on<T>(AnamEvent.xxx)` which returns a `Stream<T>`:

```dart
// Message history updates
client.on<List<Message>>(AnamEvent.messageHistoryUpdated).listen((messages) {
  setState(() => _messages = messages);
});

// Connection lifecycle
client.on(AnamEvent.connectionEstablished).listen((_) {
  print('WebRTC connected');
});

client.on(AnamEvent.connectionClosed).listen((_) {
  print('Session ended');
});

// Stream events
client.on(AnamEvent.videoStreamStarted).listen((_) {
  print('Video stream is live');
});

client.on(AnamEvent.sessionReady).listen((_) {
  print('Avatar session is ready');
});

// Avatar state
client.on(AnamEvent.personaTalking).listen((_) {
  print('Avatar is speaking');
});

client.on(AnamEvent.personaListening).listen((_) {
  print('Avatar is listening');
});

// Errors and warnings
client.on(AnamEvent.error).listen((error) {
  print('Error: $error');
});

client.on(AnamEvent.warning).listen((warning) {
  print('Warning: $warning');
});
```

### Available Events

| Event                   | Payload         | Description             |
| ----------------------- | --------------- | ----------------------- |
| `messageHistoryUpdated` | `List<Message>` | Message history changed |
| `connectionEstablished` | —               | WebRTC connected        |
| `connectionClosed`      | —               | Session ended           |
| `videoStreamStarted`    | `MediaStream`   | Video stream is active  |
| `audioStreamStarted`    | —               | Audio stream is active  |
| `sessionReady`          | `Map`           | Avatar session is ready |
| `personaTalking`        | —               | Avatar began speaking   |
| `personaListening`      | —               | Avatar is now listening |
| `inputAudioEnabled`     | —               | Microphone enabled      |
| `inputAudioDisabled`    | —               | Microphone disabled     |
| `error`                 | `dynamic`       | An error occurred       |
| `warning`               | `dynamic`       | A non-fatal warning     |

## Custom Audio (Bring Your Own Transcription)

Disable the client microphone to implement your own speech recognition, VAD, or custom turn-taking logic. The avatar's audio is still received and played; only outbound mic capture is disabled.

```dart
final client = AnamClientFactory.createClient(
  sessionToken: sessionToken,
  disableClientAudio: true,
);

await client.talk(
  personaConfig: personaConfig,
  onStreamReady: (stream) { /* ... */ },
);
```

With `disableClientAudio: true`:

- No microphone permission is requested
- Audio transceiver is set to `recvonly`
- Data channel remains available for sending messages

Send audio chunks directly to the avatar's lip-sync engine (Brain-less mode):

```dart
// Send PCM audio chunk (pcm_s16le, 24 kHz, mono)
client.appendInputAudio(Uint8List audioBytes);

// Signal end of a speech turn
client.endAgentAudioSequence();
```

## API Reference

### `AnamClientFactory`

| Method                                                            | Description                                              |
| ----------------------------------------------------------------- | -------------------------------------------------------- |
| `createClient({sessionToken, enableLogging, disableClientAudio})` | Create a client with a session token (recommended)       |
| `createClientWithOptions({sessionToken, personaId, ...})`         | Create a client with a default persona baked in          |
| `unsafeCreateClientWithApiKey({apiKey, enableLogging})`           | Development only — exposes your API key                  |
| `createWebRTCOffer({iceServers, disableClientAudio})`             | Generate a WebRTC offer without a full client (advanced) |

### `AnamClient`

#### Methods

| Method                                                                 | Description                                          |
| ---------------------------------------------------------------------- | ---------------------------------------------------- |
| `talk({personaConfig, onStreamReady, preNegotiatedSession, proxyUrl})` | Start an avatar session                              |
| `stopStreaming([reason])`                                              | End the current session                              |
| `sendUserMessage(content)`                                             | Send a text message to the avatar                    |
| `interruptPersona()`                                                   | Interrupt the avatar while it is speaking            |
| `setInputAudioEnabled(bool)`                                           | Enable or disable the microphone                     |
| `muteInputAudio()`                                                     | Mute the microphone                                  |
| `unmuteInputAudio()`                                                   | Unmute the microphone                                |
| `appendInputAudio(Uint8List)`                                          | Stream raw PCM audio to the avatar (Brain-less mode) |
| `endAgentAudioSequence()`                                              | Signal end of a speech turn (Brain-less mode)        |
| `streamToVideoElement(renderer)`                                       | Attach the remote stream to a renderer               |
| `on<T>(AnamEvent)`                                                     | Subscribe to an event, returns `Stream<T>`           |
| `dispose()`                                                            | Stop the session and release all resources           |

#### Properties

| Property            | Type             | Description                            |
| ------------------- | ---------------- | -------------------------------------- |
| `isSessionActive`   | `bool`           | Whether a session is currently running |
| `isConnected`       | `bool`           | Whether WebRTC is connected            |
| `isDataChannelOpen` | `bool`           | Whether the data channel is open       |
| `inputAudioEnabled` | `bool`           | Whether the microphone is active       |
| `messageHistory`    | `List<Message>`  | Read-only message history              |
| `currentPersona`    | `PersonaConfig?` | Active persona configuration           |
| `currentSessionId`  | `String?`        | Active session ID                      |

### `PersonaConfig`

```dart
PersonaConfig({
  required String personaId,         // Anam persona ID
  required String name,              // Display name
  required String avatarId,          // Avatar asset ID
  required String voiceId,           // Voice asset ID
  String? llmId,                     // Override the default LLM
  String? systemPrompt,              // System prompt for the avatar
  int? maxSessionLengthSeconds,      // Session timeout
  String? languageCode,              // e.g. 'en-US'
})
```

### `AnamAvatarView`

```dart
AnamAvatarView({
  required RTCVideoRenderer? renderer,  // Video renderer (null shows placeholder)
  bool showControls = true,             // Show the mic toggle button
  VoidCallback? onMicToggle,            // Callback for the mic button
  bool isMicEnabled = true,             // Current mic state (controls button icon)
  double borderRadius = 12.0,           // Corner radius
  Color backgroundColor = Colors.black, // Background color
})
```

### `Message`

```dart
class Message {
  final String id;
  final MessageRole role;    // MessageRole.user | MessageRole.assistant
  final String content;
  final DateTime timestamp;
}
```

## Contributing

[![Contributors](https://raw.githubusercontent.com/DevCodeSpace/flutter_anam_sdk/main/screenshots/contributors.png)](https://github.com/DevCodeSpace/flutter_anam_sdk/graphs/contributors)

Contributions are welcome! Please open an issue or submit a pull request on [GitHub](https://github.com/DevCodeSpace/flutter_anam_sdk).

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ by [DevCodeSpace](https://github.com/DevCodeSpace)**

</div>
