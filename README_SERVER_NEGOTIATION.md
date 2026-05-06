# Flutter Anam SDK - Server-Side Session Management with WebSocket Proxy

This document explains how to use the Flutter Anam SDK with server-side session management and WebSocket proxying.

## Overview

The Flutter Anam SDK now supports two modes of operation:

1. **Client-Side Management** (default): The Flutter app handles all API calls and WebSocket connections directly
2. **Server-Side Management with Proxy**: Your backend server creates the session and proxies the WebSocket connection

## Server-Side Session Management Flow

### 1. Create Session on Your Server

```dart
// Call your server endpoint to create a session
final response = await http.post(
  Uri.parse('http://your-server/v1/engine/session'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'personaId': 'your-persona-id',
  }),
);

final sessionData = jsonDecode(response.body);
```

### 2. Your Server Creates the Session

Your server should:

- Get a session token from Anam API using your API key
- Create an engine session with Anam
- Return the session data to the client

### 3. Create Client and Connect via Proxy

```dart
// Create client with session token
final client = AnamClientFactory.createClient(
  sessionToken: sessionData['sessionToken'],
  apiBaseUrl: 'https://api.anam.ai',
);

// Use talk() with session data and proxy WebSocket URL
await client.talk(
  preNegotiatedSession: sessionData,
  proxyUrl: 'ws://your-server/ws/proxy',
  onStreamReady: (stream) {
    // Handle video stream
  },
);
```

The client will:

- Connect to your server's WebSocket proxy endpoint
- Handle all WebRTC negotiation as normal
- Your server proxies messages between the client and Anam

## Example Server Implementation (Hono/Cloudflare Workers)

### Session Creation Endpoint

```typescript
app.post("/v1/engine/session", async (c) => {
  const { personaId } = await c.req.json();

  // Get session token
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

  // Return session data to client
  return c.json({
    ...sessionData,
    sessionToken,
  });
});
```

### WebSocket Proxy Endpoint

```typescript
app.get(
  "/ws/proxy",
  upgradeWebSocket((c) => {
    let anamWs: WebSocket | null = null;

    return {
      onOpen: async (event, ws) => {
        // Get connection parameters from query string
        const url = new URL(c.req.url);
        const engineHost = url.searchParams.get("engineHost");
        const signallingEndpoint = url.searchParams.get("signallingEndpoint");
        const sessionId = url.searchParams.get("session_id");

        // Connect to Anam WebSocket
        const anamWsUrl = `wss://${engineHost}${signallingEndpoint}?session_id=${sessionId}`;
        anamWs = new WebSocket(anamWsUrl);

        // Proxy messages between client and Anam
        anamWs.onmessage = (event) => ws.send(event.data);
        anamWs.onclose = () => ws.close();
      },

      onMessage: (event, ws) => {
        // Forward client messages to Anam
        if (anamWs?.readyState === 1) {
          anamWs.send(event.data);
        }
      },

      onClose: () => {
        anamWs?.close();
      },
    };
  }),
);
```

## Benefits of Server-Side Session Management

- Keep your Anam API key secure on the server
- Control session creation and management server-side
- Add custom authentication/authorization
- Log and monitor all WebSocket messages
- Implement rate limiting and usage controls
- Process/modify messages in transit if needed
