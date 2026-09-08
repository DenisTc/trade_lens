/// Live-data connection state as the UI sees it (a dot in the app bar).
/// Mirrors the WebSocket client without importing it: the domain stays
/// free of transport packages.
enum ConnectionStatus { idle, connecting, connected, reconnecting, suspended }
