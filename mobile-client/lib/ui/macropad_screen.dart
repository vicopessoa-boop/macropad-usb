import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/macro_action.dart';
import '../models/macro_key.dart';
import '../models/status_update.dart';
import '../services/default_layers.dart';
import '../services/macropad_connection.dart';
import '../services/voice_service.dart';
import 'components/claude_visor.dart';
import 'components/connection_badge.dart';
import 'components/layer_bar.dart';
import 'components/neon_key.dart';
import 'components/settings_sheet.dart';
import 'palette.dart';

class MacropadScreen extends StatefulWidget {
  final MacropadConnection connection;
  const MacropadScreen({super.key, required this.connection});

  @override
  State<MacropadScreen> createState() => _MacropadScreenState();
}

class _MacropadScreenState extends State<MacropadScreen> with SingleTickerProviderStateMixin {
  // Um único relógio para o pulso idle de todas as teclas (cada uma aplica sua fase).
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat();

  late List<Layer> _layers = widget.connection.remoteLayers.value ?? defaultLayers;
  int _current = 0;
  final Map<String, StatusUpdate> _statuses = {};
  StatusUpdate? _console;

  // Ditado (tecla de voz, aperte e segure para falar).
  final VoiceService _voice = VoiceService();
  bool _voiceHeld = false;
  bool _voiceFinished = true;
  String _voicePartial = '';
  Timer? _voiceTimeout;
  late final StreamSubscription<StatusUpdate> _statusSub;

  MacropadConnection get _conn => widget.connection;

  @override
  void initState() {
    super.initState();
    _statusSub = _conn.statusUpdates.listen(_onStatus);
    _conn.remoteLayers.addListener(_onRemoteLayers);
  }

  void _onRemoteLayers() {
    final remote = _conn.remoteLayers.value;
    if (remote == null) return;
    setState(() {
      final currentId = _layers[_current].id;
      _layers = remote;
      final idx = remote.indexWhere((l) => l.id == currentId);
      _current = idx >= 0 ? idx : 0;
    });
  }

  void _onStatus(StatusUpdate s) {
    setState(() {
      _statuses[s.buttonId] = s;
      // Mensagens de shell (saída do comando) e erros aparecem no console inferior.
      if ((s.message?.isNotEmpty ?? false) || s.status == KeyStatus.error) _console = s;
    });
  }

  void _setLocalStatus(MacroKey key, KeyStatus st, String msg) {
    setState(() {
      final s = StatusUpdate(buttonId: key.id, status: st, color: StatusUpdate.defaultColor(st), message: msg);
      _statuses[key.id] = s;
      _console = s;
    });
  }

  /// Apertou a tecla de voz: começa a ouvir.
  Future<void> _voiceStart(MacroKey key) async {
    if (_conn.phase != ConnectionPhase.connected) {
      _showNoConnection();
      return;
    }
    _voiceHeld = true;
    _voiceFinished = false;
    _voicePartial = '';
    _voiceTimeout?.cancel();
    _setLocalStatus(key, KeyStatus.running, '🎤 Ouvindo… solte para enviar');
    final ok = await _voice.start(
      localeId: (key.action.payload['locale'] as String?) ?? 'pt_BR',
      onPartial: (t) {
        _voicePartial = t;
        if (!_voiceFinished) _setLocalStatus(key, KeyStatus.running, '🎤 $t');
      },
      onFinal: (t) => _voiceFinish(key, t.isNotEmpty ? t : _voicePartial),
      onError: (e) {
        if (!_voiceFinished && _voicePartial.isEmpty) {
          _voiceFinished = true;
          _setLocalStatus(key, KeyStatus.error, 'Não entendi ($e). Tente de novo.');
        }
      },
    );
    if (!ok) {
      _voiceFinished = true;
      _setLocalStatus(key, KeyStatus.error, 'Microfone indisponível: permita o acesso ao microfone para o Ananda.');
      return;
    }
    // Soltou antes de o microfone terminar de abrir.
    if (!_voiceHeld) _voiceStop(key);
  }

  /// Soltou a tecla de voz: para de ouvir e envia o texto.
  void _voiceStop(MacroKey key) {
    _voiceHeld = false;
    if (_voiceFinished) return;
    _voice.stop();
    // Se o resultado final não vier, usa o último texto parcial.
    _voiceTimeout?.cancel();
    _voiceTimeout = Timer(const Duration(milliseconds: 2500), () => _voiceFinish(key, _voicePartial));
  }

  void _voiceFinish(MacroKey key, String text) {
    if (_voiceFinished) return;
    _voiceFinished = true;
    _voiceTimeout?.cancel();
    if (text.trim().isEmpty) {
      _setLocalStatus(key, KeyStatus.error, 'Nada reconhecido. Segure a tecla enquanto fala.');
      return;
    }
    // Cola o texto na janela em foco do computador (ex.: Claude Code).
    _setLocalStatus(key, KeyStatus.running, '🎤 $text');
    _conn.sendAction(key.id, MacroAction.snippet(text, indent: false));
  }

  void _trigger(MacroKey key, [MacroAction? action]) {
    if ((action ?? key.action).isVoice) {
      _voiceStart(key);
      return;
    }
    if (!_conn.sendAction(key.id, action ?? key.action)) _showNoConnection();
  }

  void _showNoConnection() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Sem conexão com o desktop. Verifique o cabo e o daemon.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _voiceTimeout?.cancel();
    _conn.remoteLayers.removeListener(_onRemoteLayers);
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = _layers[_current];
    return Scaffold(
      backgroundColor: Palette.background,
      body: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: layer.color),
        duration: const Duration(milliseconds: 400),
        builder: (context, tint, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.1),
              radius: 1.4,
              colors: [(tint ?? layer.color).withValues(alpha: 0.10), Palette.background],
            ),
          ),
          child: child,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                child: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'ANANDA',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: Palette.textStrong,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    ConnectionBadge(connection: _conn, onTap: () => showSettingsSheet(context, _conn)),
                  ],
                ),
              ),
              LayerBar(layers: _layers, current: _current, onSelect: (i) => setState(() => _current = i)),
              if (layer.visor == 'claude')
                ListenableBuilder(
                  listenable: _conn,
                  builder: (context, _) => ClaudeVisor(
                    sessions: _conn.claudeSessions,
                    connected: _conn.phase == ConnectionPhase.connected,
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _conn,
                  builder: (context, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
                    ),
                    child: _KeyGrid(
                      key: ValueKey(layer.id),
                      layer: layer,
                      statuses: _statuses,
                      idle: _idle,
                      enabled: _conn.phase == ConnectionPhase.connected,
                      onTrigger: _trigger,
                      onVoiceRelease: _voiceStop,
                    ),
                  ),
                ),
              ),
              _Console(status: _console),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grade de teclas quadradas que ocupa o máximo do espaço disponível.
class _KeyGrid extends StatelessWidget {
  final Layer layer;
  final Map<String, StatusUpdate> statuses;
  final Animation<double> idle;
  final bool enabled;
  final void Function(MacroKey, [MacroAction?]) onTrigger;
  final void Function(MacroKey) onVoiceRelease;

  const _KeyGrid({
    super.key,
    required this.layer,
    required this.statuses,
    required this.idle,
    required this.enabled,
    required this.onTrigger,
    required this.onVoiceRelease,
  });

  @override
  Widget build(BuildContext context) {
    final cols = layer.columns;
    final rows = math.max(1, (layer.keys.length / cols).ceil());
    const gap = 16.0;
    const pad = 20.0;

    return LayoutBuilder(
      builder: (context, c) {
        final cellW = (c.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
        final cellH = (c.maxHeight - pad * 2 - gap * (rows - 1)) / rows;
        final cell = math.max(40.0, math.min(cellW, cellH));
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : gap),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var col = 0; col < cols; col++)
                        Padding(
                          padding: EdgeInsets.only(left: col == 0 ? 0 : gap),
                          child: SizedBox.square(dimension: cell, child: _buildKey(r * cols + col, cols)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildKey(int index, int cols) {
    if (index >= layer.keys.length) return null;
    final k = layer.keys[index];
    if (k.spacer) return null;
    return NeonKey(
      key: ValueKey(k.id),
      macroKey: k,
      color: k.color ?? layer.color,
      status: statuses[k.id],
      idle: idle,
      // Fase diagonal: o pulso idle percorre o teclado como uma onda.
      phase: ((index ~/ cols) + (index % cols)) * 0.08,
      enabled: enabled,
      onTrigger: () => onTrigger(k),
      onHoldTrigger: k.holdAction == null ? null : () => onTrigger(k, k.holdAction),
      onRelease: k.action.isVoice ? () => onVoiceRelease(k) : null,
    );
  }
}

/// Última saída de comando de shell / erro.
class _Console extends StatelessWidget {
  final StatusUpdate? status;
  const _Console({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: s == null
          ? const SizedBox(height: 12)
          : Container(
              key: ValueKey(s.receivedAt),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: s.color.withValues(alpha: 0.5)),
              ),
              child: Text(
                '${s.buttonId}  ${s.status.name.toUpperCase()}\n${s.message ?? ''}'.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.3,
                  color: Color.lerp(Palette.text, s.color, 0.35),
                ),
              ),
            ),
    );
  }
}
