import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/layer.dart';
import '../models/macro_action.dart';
import '../models/status_update.dart';

enum ConnectionPhase { disconnected, connecting, connected }

/// Conexão WebSocket com o daemon desktop.
///
/// Via cabo USB o daemon roda `adb reverse tcp:8080 tcp:8080`, então o app só precisa
/// falar com ws://127.0.0.1:8080/ws. Reconecta sozinho com backoff curto (o cabo pode
/// ser desplugado a qualquer momento) e mede a latência com PING/PONG.
class MacropadConnection extends ChangeNotifier {
  String host;
  int port;
  String token;

  MacropadConnection({this.host = '127.0.0.1', this.port = 8080, this.token = ''});

  ConnectionPhase _phase = ConnectionPhase.disconnected;
  ConnectionPhase get phase => _phase;

  /// Latência ida e volta medida pelo último PING (ms).
  int? latencyMs;
  String? serverBackend;
  String? lastError;

  /// Layers enviadas pelo desktop (config.json). Null = usar o layout local.
  final ValueNotifier<List<Layer>?> remoteLayers = ValueNotifier(null);

  final _statusCtrl = StreamController<StatusUpdate>.broadcast();
  Stream<StatusUpdate> get statusUpdates => _statusCtrl.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _attempt = 0;
  int _requestSeq = 0;
  bool _disposed = false;
  bool _wanted = false;

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/ws');

  void start() {
    _wanted = true;
    _connect();
  }

  /// Aplica novas configurações e reconecta.
  void reconfigure({required String host, required int port, required String token}) {
    this.host = host;
    this.port = port;
    this.token = token;
    _closeChannel();
    _attempt = 0;
    if (_wanted) _connect();
  }

  Future<void> _connect() async {
    if (_disposed || !_wanted) return;
    _reconnectTimer?.cancel();
    _setPhase(ConnectionPhase.connecting);
    final channel = IOWebSocketChannel.connect(
      uri,
      connectTimeout: const Duration(seconds: 2),
      pingInterval: const Duration(seconds: 10),
    );
    _channel = channel;
    try {
      await channel.ready;
    } catch (e) {
      if (!identical(_channel, channel)) return;
      lastError = 'Sem resposta em ${uri.host}:${uri.port}';
      _scheduleReconnect();
      return;
    }
    if (!identical(_channel, channel) || _disposed) return;

    _sub = channel.stream.listen(
      _onMessage,
      onDone: () => _onClosed(channel),
      onError: (Object e) => _onClosed(channel, e),
      cancelOnError: true,
    );
    // HELLO sempre: o servidor exige quando há token e ignora quando não há.
    _sendRaw({'type': 'HELLO', 'client': 'macropad-flutter', if (token.isNotEmpty) 'token': token});
    _attempt = 0;
    lastError = null;
    _setPhase(ConnectionPhase.connected);
    _pingTimer?.cancel();
    _ping();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _ping());
  }

  void _onClosed(WebSocketChannel channel, [Object? error]) {
    if (!identical(_channel, channel)) return;
    if (error != null) lastError = error.toString();
    _closeChannel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_wanted) return;
    _setPhase(ConnectionPhase.disconnected);
    // 300 ms, 600 ms, 1,2 s... limitado a 3 s: ao replugar o cabo a volta é quase imediata.
    final delayMs = (300 * (1 << _attempt.clamp(0, 4))).clamp(300, 3000);
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _connect);
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    latencyMs = null;
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'STATUS_UPDATE':
        final s = StatusUpdate.fromJson(msg);
        if (s != null) _statusCtrl.add(s);
      case 'PONG':
        final ts = (msg['ts'] as num?)?.toInt();
        if (ts != null) {
          latencyMs = DateTime.now().millisecondsSinceEpoch - ts;
          notifyListeners();
        }
      case 'HELLO':
        serverBackend = msg['backend'] as String?;
        notifyListeners();
      case 'LAYOUT':
        final layers = msg['layers'];
        if (layers is List && layers.isNotEmpty) {
          try {
            remoteLayers.value = Layer.listFromJson(layers);
          } catch (e) {
            debugPrint('LAYOUT inválido: $e');
          }
        }
      case 'ERROR':
        lastError = msg['message'] as String?;
        notifyListeners();
    }
  }

  void _ping() => _sendRaw({'type': 'PING', 'ts': DateTime.now().millisecondsSinceEpoch});

  /// Envia a ação. Retorna false se não houver conexão.
  bool sendAction(String buttonId, MacroAction action) {
    if (_phase != ConnectionPhase.connected) return false;
    _requestSeq++;
    return _sendRaw(action.toMessage(buttonId: buttonId, requestId: 'r$_requestSeq'));
  }

  bool _sendRaw(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setPhase(ConnectionPhase p) {
    if (_phase == p) return;
    _phase = p;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _wanted = false;
    _reconnectTimer?.cancel();
    _closeChannel();
    _statusCtrl.close();
    remoteLayers.dispose();
    super.dispose();
  }
}
