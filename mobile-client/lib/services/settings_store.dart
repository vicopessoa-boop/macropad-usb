import 'package:shared_preferences/shared_preferences.dart';

/// Endereço do daemon e token, persistidos no aparelho.
class ConnectionSettings {
  final String host;
  final int port;
  final String token;

  /// Porta padrão; pode ser trocada no build: flutter build apk --dart-define=MACROPAD_PORT=8091
  static const defaultPort = int.fromEnvironment('MACROPAD_PORT', defaultValue: 8080);

  const ConnectionSettings({this.host = '127.0.0.1', this.port = defaultPort, this.token = ''});

  static const _kHost = 'host', _kPort = 'port', _kToken = 'token';

  static Future<ConnectionSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return ConnectionSettings(
        host: p.getString(_kHost) ?? '127.0.0.1',
        port: p.getInt(_kPort) ?? defaultPort,
        token: p.getString(_kToken) ?? '',
      );
    } catch (_) {
      return const ConnectionSettings();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, host);
    await p.setInt(_kPort, port);
    await p.setString(_kToken, token);
  }
}
