import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;


typedef EventCallback = void Function(dynamic data);

class SocketService {
  static io.Socket? _socket;
  static bool _connected = false;

  // Use your computer's IP for local testing on a physical device, or your Render URL
  // static const String serverUrl = 'https://alerto-poz.onrender.com'; // Production
  // static const String serverUrl = 'http://localhost:3000'; // Web / iOS Emulator
  static const String serverUrl = 'http://192.168.100.131:3000'; // Local Network IP (Works for Web & Physical Phone)

  static bool get isConnected => _connected;

  static void init() {
    if (_socket != null) return;

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(10)
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      debugPrint('[Socket] Connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('[Socket] Disconnected');
    });

    _socket!.onConnectError((err) {
      _connected = false;
      debugPrint('[Socket] Connect error: $err');
    });

    _socket!.connect();
  }

  static void on(String event, EventCallback callback) {
    _socket?.on(event, callback);
  }

  static void off(String event) {
    _socket?.off(event);
  }

  static void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  /// Emit with acknowledgement callback — used for SOS report to get real ticket ID
  /// Web equivalent: socket.emit('citizen-sos-report', payload, (response) => { ... })
  static void emitWithAck(String event, dynamic data, Function(dynamic) ack) {
    _socket?.emitWithAck(event, data).then((response) {
      ack(response);
    }).catchError((e) {
      debugPrint('[Socket] emitWithAck error: $e');
      ack(null);
    });
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }

  // ───────── Convenience emitters ─────────

  /// Emit SOS report WITHOUT callback (for follow-up messages)
  static void emitSosReport(Map<String, dynamic> payload) {
    emit('citizen-sos-report', payload);
  }

  /// Emit SOS report WITH callback (for first activation — gets real ticket ID)
  /// Web: socket.emit('citizen-sos-report', this.activeIncident, async (response) => { ... })
  static void emitSosReportWithAck(Map<String, dynamic> payload, Function(dynamic) ack) {
    emitWithAck('citizen-sos-report', payload, ack);
  }

  static void emitCallStatus(Map<String, dynamic> payload) {
    emit('citizen-call-status-change', payload);
  }

  static void emitCheckin(Map<String, dynamic> payload) {
    emit('citizen-checkin-alert', payload);
  }

  // ───────── Convenience listeners (EXACT web event names) ─────────

  /// Web: socket.on('broadcast-advisory', (data) => { ... })
  static void onBroadcastAdvisory(EventCallback cb) => on('broadcast-advisory', cb);

  /// Web: socket.on('chat-message-receive', (msg) => { ... })
  static void onChatMessageReceive(EventCallback cb) => on('chat-message-receive', cb);

  /// Web: socket.on('incident-updated', (incident) => { ... })
  static void onIncidentUpdated(EventCallback cb) => on('incident-updated', cb);

  /// Web: socket.on('init-state', (db) => { ... })
  static void onInitState(EventCallback cb) => on('init-state', cb);

  /// Web: socket.on('responder-updated', (responder) => { ... })
  static void onResponderUpdated(EventCallback cb) => on('responder-updated', cb);

  /// Web: socket.on('profile-updated', (user) => { ... })
  static void onProfileUpdated(EventCallback cb) => on('profile-updated', cb);

  /// Web: socket.on('call-status-updated', (data) => { ... })
  static void onCallStatusUpdated(EventCallback cb) => on('call-status-updated', cb);

  // ───────── Legacy listeners (kept for backward compatibility) ─────────

  static void onBroadcastAlert(EventCallback cb) => on('broadcast-alert', cb);
  static void onCallStatusChange(EventCallback cb) => on('call-status-change', cb);
  static void onIncidentAck(EventCallback cb) => on('incident-ack', cb);
  static void onDispatchUpdate(EventCallback cb) => on('dispatch-update', cb);
}
