import 'package:flutter/material.dart';

import '../../services/macropad_connection.dart';
import '../palette.dart';

/// Indicador de conexão: LED + estado + latência. Toque para abrir as configurações.
class ConnectionBadge extends StatelessWidget {
  final MacropadConnection connection;
  final VoidCallback onTap;

  const ConnectionBadge({super.key, required this.connection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final (color, text) = switch (connection.phase) {
          ConnectionPhase.connected => (
              const Color(0xFF00A859),
              connection.latencyMs == null ? 'USB conectado' : 'USB · ${connection.latencyMs} ms',
            ),
          ConnectionPhase.connecting => (const Color(0xFFE09A00), 'Conectando…'),
          ConnectionPhase.disconnected => (const Color(0xFFE5243F), 'Desconectado'),
        };
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: color, blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(color: Palette.text, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
