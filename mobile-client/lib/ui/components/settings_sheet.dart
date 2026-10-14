import 'package:flutter/material.dart';

import '../../services/macropad_connection.dart';
import '../../services/settings_store.dart';
import '../palette.dart';

/// Configuração do endereço do daemon. Via cabo (adb reverse) o padrão 127.0.0.1:8080
/// funciona sem mudanças; troque o host apenas no fallback por USB tethering.
Future<void> showSettingsSheet(BuildContext context, MacropadConnection connection) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SettingsSheet(connection: connection),
  );
}

class _SettingsSheet extends StatefulWidget {
  final MacropadConnection connection;
  const _SettingsSheet({required this.connection});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _host = TextEditingController(text: widget.connection.host);
  late final _port = TextEditingController(text: '${widget.connection.port}');
  late final _token = TextEditingController(text: widget.connection.token);

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim()) ?? ConnectionSettings.defaultPort;
    final settings = ConnectionSettings(
      host: _host.text.trim().isEmpty ? '127.0.0.1' : _host.text.trim(),
      port: port,
      token: _token.text.trim(),
    );
    await settings.save();
    widget.connection.reconfigure(host: settings.host, port: settings.port, token: settings.token);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connection;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Conexão com o desktop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Cabo USB + Depuração USB: mantenha 127.0.0.1 (o daemon faz o adb reverse).\n'
            'USB tethering: use o IP do computador na interface do tethering.',
            style: const TextStyle(color: Palette.textMuted, fontSize: 12),
          ),
          if (c.serverBackend != null) ...[
            const SizedBox(height: 6),
            Text(
              'Backend do desktop: ${c.serverBackend}',
              style: const TextStyle(color: Palette.textMuted, fontSize: 12),
            ),
          ],
          if (c.lastError != null) ...[
            const SizedBox(height: 6),
            Text(c.lastError!, style: const TextStyle(color: Color(0xFFFF2D55), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'Host'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Porta'),
                ),
              ),
            ],
          ),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Token (opcional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Salvar e reconectar')),
        ],
      ),
    );
  }
}
