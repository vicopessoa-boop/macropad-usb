import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/claude_session.dart';
import '../palette.dart';

/// Visor de status do Claude Code: uma luz por sessão (projeto).
/// Azul pulsando = trabalhando · verde = pronto · amarelo = aguardando autorização
/// · vermelho = erro / precisa de atenção. Vibra quando um estado muda.
class ClaudeVisor extends StatefulWidget {
  final ValueListenable<List<ClaudeSession>> sessions;
  final bool connected;

  const ClaudeVisor({super.key, required this.sessions, required this.connected});

  @override
  State<ClaudeVisor> createState() => _ClaudeVisorState();
}

class _ClaudeVisorState extends State<ClaudeVisor> with SingleTickerProviderStateMixin {
  static const _maxRows = 3;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  final Map<String, ClaudeState> _last = {};

  @override
  void initState() {
    super.initState();
    for (final s in widget.sessions.value) {
      _last[s.id] = s.state;
    }
    widget.sessions.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ClaudeVisor old) {
    super.didUpdateWidget(old);
    if (old.sessions != widget.sessions) {
      old.sessions.removeListener(_onChange);
      widget.sessions.addListener(_onChange);
    }
  }

  void _onChange() {
    // Vibração só nas mudanças que pedem o olhar do usuário.
    for (final s in widget.sessions.value) {
      final before = _last[s.id];
      if (before == s.state) continue;
      switch (s.state) {
        case ClaudeState.done:
          HapticFeedback.mediumImpact();
        case ClaudeState.waiting:
          HapticFeedback.heavyImpact();
        case ClaudeState.attention:
          HapticFeedback.vibrate();
        case ClaudeState.working:
        case ClaudeState.idle:
          break;
      }
    }
    _last
      ..clear()
      ..addEntries(widget.sessions.value.map((s) => MapEntry(s.id, s.state)));
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onChange);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ClaudeSession>>(
      valueListenable: widget.sessions,
      builder: (context, sessions, _) {
        final shown = sessions.take(_maxRows).toList();
        final accent = shown.isEmpty || !widget.connected ? Palette.border : _priority(shown).color;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: -2)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CLAUDE CODE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2, color: Palette.textMuted),
              ),
              const SizedBox(height: 6),
              if (!widget.connected)
                _row(null, 'Desktop desconectado', null)
              else if (shown.isEmpty)
                _row(null, 'Nenhuma sessão ativa', null)
              else
                for (final s in shown) _row(s, s.project, s.label),
              if (sessions.length > _maxRows)
                Text(
                  '+${sessions.length - _maxRows} sessões',
                  style: const TextStyle(fontSize: 11, color: Palette.textMuted),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Cor do contorno: o estado mais urgente entre as sessões.
  ClaudeSession _priority(List<ClaudeSession> s) {
    const order = [ClaudeState.attention, ClaudeState.waiting, ClaudeState.done, ClaudeState.working, ClaudeState.idle];
    for (final st in order) {
      for (final x in s) {
        if (x.state == st) return x;
      }
    }
    return s.first;
  }

  Widget _row(ClaudeSession? s, String title, String? subtitle) {
    final color = s?.color ?? Palette.textDisabled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final pulsing = s?.state == ClaudeState.working;
              final a = pulsing ? 0.35 + 0.65 * _pulse.value : 1.0;
              return Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: a),
                  boxShadow: s == null ? null : [BoxShadow(color: color.withValues(alpha: 0.6 * a), blurRadius: 10)],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.textStrong),
            ),
          ),
          if (subtitle != null)
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color.lerp(Palette.text, color, 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}
