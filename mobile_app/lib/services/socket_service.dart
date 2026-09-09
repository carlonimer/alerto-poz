import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

typedef EventCallback = void Function(dynamic data);

class SocketService {
  static io.Socket? _socket;
  static bool _connected = false;

  // Use your computer's IP for local testing on a physical device, or your Render URL
  static final String serverUrl = 'https://alerto-poz.onrender.com';

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

  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }

  // ───────── Convenience emitters ─────────

  static void emitSosReport(Map<String, dynamic> payload) {
    emit('citizen-sos-report', payload);
  }

  static void emitCallStatus(Map<String, dynamic> payload) {
    emit('citizen-call-status-change', payload);
  }

  static void emitCheckin(Map<String, dynamic> payload) {
    emit('citizen-checkin-alert', payload);
  }

  // ───────── Convenience listeners ─────────

  static void onBroadcastAlert(EventCallback cb) => on('broadcast-alert', cb);
  static void onCallStatusChange(EventCallback cb) => on('call-status-change', cb);
  static void onIncidentAck(EventCallback cb) => on('incident-ack', cb);
  static void onDispatchUpdate(EventCallback cb) => on('dispatch-update', cb);
}
