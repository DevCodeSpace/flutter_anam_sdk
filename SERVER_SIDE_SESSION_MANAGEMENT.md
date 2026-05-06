# Server-Side Session Management for Flutter Anam SDK

## Overview

The Flutter Anam SDK now supports server-side session management, where your backend server creates sessions using your API key, and the Flutter client connects directly to Anam using the session data.

## Benefits

- **Security**: Keep your API key secure on the server
- **Control**: Manage session creation and authorization server-side
- **Simplicity**: Client connects directly to Anam (no proxy needed)
- **Compatibility**: Works with all WebSocket environments

## Architecture

1. **Server creates session**: Your backend uses the API key to create a session
2. **Client receives session data**: Server returns session info to client
3. **Direct connection**: Client connects directly to Anam's WebSocket

## Implementation

### Server Endpoint (Hono/Cloudflare Workers)

```typescript
app.post("/v1/engine/session", async (c) => {
  const { personaId } = await c.req.json();

  // Get session token using your API key
  const tokenResponse = await fetch(
    "https://api.anam.ai/v1/auth/session-token",
    {
      headers: { Authorization: `Bearer ${API_KEY}` },
    },
  );
  const { sessionToken } = await tokenResponse.json();

  // Create engine session
  const sessionResponse = await fetch("https://api.anam.ai/v1/engine/session", {
    method: "POST",
    headers: { Authorization: `Bearer ${sessionToken}` },
    body: JSON.stringify({ personaConfig: { personaId } }),
  });

  const sessionData = await sessionResponse.json();

  // Return session data including token
  return c.json({
    ...sessionData,
    sessionToken,
  });
});
```

### Flutter Client

```dart
// 1. Create session on your server
final response = await http.post(
  Uri.parse('http://your-server/v1/engine/session'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'personaId': 'your-persona-id'}),
);

final sessionData = jsonDecode(response.body);

// 2. Create client with session token
final client = AnamClientFactory.createClient(
  sessionToken: sessionData['sessionToken'],
);

// 3. Connect using session data
await client.talk(
  preNegotiatedSession: sessionData,
  onStreamReady: (stream) {
    // Handle video stream
  },
);
```

## How It Works

1. Flutter app calls your server endpoint
2. Server uses API key to get session token from Anam
3. Server creates engine session with Anam
4. Server returns session data to Flutter app
5. Flutter app creates client with session token
6. Flutter app connects directly to Anam's WebSocket using session data

## Notes

- No WebSocket proxy needed - client connects directly to Anam
- Works in all environments (Cloudflare Workers, Node.js, etc.)
- Session management and authorization happen on your server
- Client handles all WebRTC negotiation as normal
