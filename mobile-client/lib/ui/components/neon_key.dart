import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/macro_key.dart';
import '../../models/status_update.dart';
import '../palette.dart';

/// Keycap mecânico com retroiluminação RGB.
///
/// - Idle: pulso sutil de brilho (fase defasada por tecla, criando uma "onda").
/// - Press down: o keycap afunda, o brilho dispara e há um ripple de luz no ponto do toque
///   + HapticFeedback.heavyImpact. A ação é disparada no toque (não no soltar) para
///   minimizar a latência, como num teclado de verdade.
/// - Release: a luz dissipa devagar + HapticFeedback.lightImpact.
/// - STATUS_UPDATE: RUNNING pulsa na cor do status; SUCCESS/ERROR acendem e esmaecem.
/// - Teclas com `confirm`: é preciso segurar ~0,6 s (anel de progresso na borda).
/// - Teclas com `hold_action`: toque rápido = ação normal (ao soltar); segurar
///   `hold_ms` (padrão 2 s) = ação extra, com anel de progresso e vibração.
class NeonKey extends StatefulWidget {
  final MacroKey macroKey;
  final Color color;
  final StatusUpdate? status;
  final Animation<double> idle;
  final double phase;
  final bool enabled;
  final VoidCallback onTrigger;

  /// Chamado ao segurar a tecla pelo tempo de `hold_ms` (só teclas com `hold_action`).
  final VoidCallback? onHoldTrigger;

  const NeonKey({
    super.key,
    required this.macroKey,
    required this.color,
    required this.idle,
    required this.onTrigger,
    this.onHoldTrigger,
    this.status,
    this.phase = 0,
    this.enabled = true,
  });

  @override
  State<NeonKey> createState() => _NeonKeyState();
}

class _NeonKeyState extends State<NeonKey> with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 600);

  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 60),
    reverseDuration: const Duration(milliseconds: 520),
  );
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: 1,
  );
  late final AnimationController _running = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _hold = AnimationController(vsync: this, duration: _holdDuration);

  int? _pointer;
  Offset _touch = Offset.zero;
  bool _firedThisPress = false;

  @override
  void initState() {
    super.initState();
    _hold.addStatusListener((s) {
      if (s != AnimationStatus.completed || _pointer == null || _firedThisPress) return;
      if (widget.macroKey.confirm) {
        _fire();
      } else if (_hasHold) {
        _fireHold();
      }
    });
    _applyStatus(widget.status);
  }

  @override
  void didUpdateWidget(NeonKey old) {
    super.didUpdateWidget(old);
    if (!identical(old.status, widget.status)) _applyStatus(widget.status);
  }

  void _applyStatus(StatusUpdate? s) {
    if (s == null) {
      _running.stop();
      _running.value = 0;
      return;
    }
    switch (s.status) {
      case KeyStatus.running:
        if (!_running.isAnimating) _running.repeat(reverse: true);
      case KeyStatus.success:
      case KeyStatus.error:
        _running.stop();
        _running.value = 0;
        // Só pisca para status novos (não ao reconstruir a tecla com um status antigo).
        if (DateTime.now().difference(s.receivedAt) < const Duration(seconds: 2)) {
          _flash.forward(from: 0);
          if (s.status == KeyStatus.error) {
            HapticFeedback.vibrate();
          } else if (widget.macroKey.action.isShell) {
            HapticFeedback.selectionClick();
          }
        }
    }
  }

  bool get _hasHold => widget.macroKey.holdAction != null && widget.onHoldTrigger != null;

  void _fireHold() {
    _firedThisPress = true;
    HapticFeedback.heavyImpact();
    _ripple.forward(from: 0);
    widget.onHoldTrigger!();
  }

  void _fire() {
    _firedThisPress = true;
    HapticFeedback.heavyImpact();
    _ripple.forward(from: 0);
    widget.onTrigger();
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    if (!widget.enabled) {
      // Desconectado: sem animação de disparo, mas o pai avisa o usuário.
      HapticFeedback.selectionClick();
      widget.onTrigger();
      return;
    }
    _pointer = e.pointer;
    _touch = e.localPosition;
    _firedThisPress = false;
    _press.forward();
    if (widget.macroKey.confirm) {
      HapticFeedback.selectionClick();
      _hold.duration = _holdDuration;
      _hold.forward(from: 0);
    } else if (_hasHold) {
      // A ação normal espera o soltar: só assim dá para saber se foi toque ou segurar.
      _hold.duration = Duration(milliseconds: widget.macroKey.holdMs);
      _hold.forward(from: 0);
    } else {
      _fire();
    }
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _press.reverse();
    if (_hasHold && !_firedThisPress) {
      _hold.value = 0;
      _fire();
      HapticFeedback.lightImpact();
    } else if (widget.macroKey.confirm && !_firedThisPress) {
      _hold.animateBack(0, duration: const Duration(milliseconds: 180));
    } else {
      _hold.value = 0;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _ripple.dispose();
    _flash.dispose();
    _running.dispose();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.macroKey;
    final icon = keyIcons[key.icon];
    return Semantics(
      button: true,
      label: key.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_press, _ripple, _flash, _running, _hold, widget.idle]),
            builder: (context, _) {
              final s = widget.status;
              final press = Curves.easeOut.transform(_press.value);
              final idle = 0.5 + 0.5 * math.sin(2 * math.pi * (widget.idle.value + widget.phase));

              // Mistura da cor de status: RUNNING pulsa; SUCCESS/ERROR seguram 35% do tempo e esmaecem.
              double statusMix = 0;
              if (s != null && s.status == KeyStatus.running) {
                statusMix = 0.55 + 0.45 * _running.value;
              } else if (s != null) {
                final t = ((_flash.value - 0.35) / 0.65).clamp(0.0, 1.0);
                statusMix = 1 - Curves.easeIn.transform(t);
              }
              final light = s == null ? widget.color : Color.lerp(widget.color, s.color, statusMix)!;
              final glow =
                  widget.enabled ? (0.22 + 0.14 * idle + 0.75 * press + 0.65 * statusMix).clamp(0.0, 1.4) : 0.08;
              const travel = 4.0;
              final dy = travel * press;

              return CustomPaint(
                painter: KeycapPainter(
                  color: widget.enabled ? light : Color.lerp(light, Colors.grey, 0.7)!,
                  glow: glow,
                  press: press,
                  ripple: _ripple.isAnimating ? _ripple.value : 0,
                  touch: _touch,
                  // Teclas com hold_action: o anel só aparece depois de um instante, para um
                  // toque rápido não piscar o anel.
                  hold: key.confirm
                      ? _hold.value
                      : _hasHold
                          ? ((_hold.value - 0.12) / 0.88).clamp(0.0, 1.0)
                          : 0,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(6, 6 + dy, 6, 14 - dy),
                      child: _Legend(
                        label: key.label,
                        icon: icon,
                        color: light,
                        glow: glow,
                        press: press,
                        enabled: widget.enabled,
                        badge: _badge(s, statusMix),
                      ),
                    ),
                    // Indica que segurar a tecla tem uma segunda função (Enter).
                    if (_hasHold)
                      Positioned(
                        top: 9 + dy,
                        right: 11,
                        child: Icon(Icons.keyboard_return_rounded, size: 14, color: light.withValues(alpha: 0.75)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String? _badge(StatusUpdate? s, double mix) {
    if (s == null || !widget.macroKey.action.isShell) return null;
    switch (s.status) {
      case KeyStatus.running:
        return 'rodando…';
      case KeyStatus.success:
      case KeyStatus.error:
        if (mix <= 0.01) return null;
        final ok = s.status == KeyStatus.success ? 'OK' : 'ERRO';
        final ms = s.elapsedMs;
        if (ms == null) return ok;
        return ms < 1000 ? '$ok ${ms}ms' : '$ok ${(ms / 1000).toStringAsFixed(1)}s';
    }
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final double glow;
  final double press;
  final bool enabled;
  final String? badge;

  const _Legend({
    required this.label,
    required this.icon,
    required this.color,
    required this.glow,
    required this.press,
    required this.enabled,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        enabled ? Color.lerp(Palette.text, Palette.textStrong, (glow - 0.2).clamp(0.0, 1.0))! : Palette.textDisabled;
    // No fundo claro o brilho da legenda é discreto: um halo leve na cor da tecla.
    final shadows = [
      Shadow(
        color: color.withValues(alpha: (0.35 * glow).clamp(0.0, 1.0)),
        blurRadius: 4 + 6 * glow,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final base = math.min(c.maxWidth, c.maxHeight);
        // scaleDown: em teclas pequenas a legenda encolhe em vez de vazar da tecla.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: base * 0.30, color: enabled ? color : textColor, shadows: shadows),
                if (icon != null) SizedBox(height: base * 0.05),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: (base * 0.13).clamp(10.0, 16.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    shadows: shadows,
                  ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: (base * 0.10).clamp(9.0, 12.0),
                        fontWeight: FontWeight.w700,
                        shadows: shadows,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Desenha o keycap: bloom, saia (profundidade), topo com gradiente, luz interna,
/// ripple do toque, borda neon e anel de progresso (teclas com confirmação).
class KeycapPainter extends CustomPainter {
  final Color color;
  final double glow;
  final double press;
  final double ripple;
  final Offset touch;
  final double hold;

  KeycapPainter({
    required this.color,
    required this.glow,
    required this.press,
    required this.ripple,
    required this.touch,
    required this.hold,
  });

  static const _skirtDepth = 8.0;
  static const _travel = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final g = glow.clamp(0.0, 1.4);
    final g1 = g.clamp(0.0, 1.0);
    final dy = _travel * press;

    final skirt = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, _skirtDepth / 2, size.width, size.height - _skirtDepth / 2),
      const Radius.circular(16),
    );
    final capRect = Rect.fromLTWH(3, dy, size.width - 6, size.height - _skirtDepth - _travel + 2);
    final cap = RRect.fromRectAndRadius(capRect, const Radius.circular(13));

    // 1. Bloom: halo colorido desfocado atrás da tecla (o "vazamento" do LED).
    canvas.drawRRect(
      skirt.inflate(1),
      Paint()
        ..color = color.withValues(alpha: (0.38 * g).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 12 * g),
    );

    // 2. Saia do keycap (profundidade) com um fio de cor por baixo.
    canvas.drawRRect(skirt, Paint()..color = Color.lerp(Palette.capSkirt, color, 0.25)!);
    canvas.drawRRect(
      skirt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.25 + 0.35 * g1),
    );

    // 3. Topo do keycap: plástico claro, tingido pela cor da tecla quando pressionado.
    final top = Color.lerp(Palette.capTop, color, 0.14 * press + 0.04 * g1)!;
    final bottom = Color.lerp(Palette.capBottom, color, 0.10 * press + 0.03 * g1)!;
    canvas.drawRRect(
      cap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(capRect),
    );

    // 4. Luz interna atravessando a legenda (retroiluminação).
    canvas.save();
    canvas.clipRRect(cap);
    canvas.drawRect(
      capRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 0.8,
          colors: [
            color.withValues(alpha: 0.14 * g1),
            color.withValues(alpha: 0),
          ],
        ).createShader(capRect),
    );

    // 5. Ripple de luz a partir do ponto tocado.
    if (ripple > 0) {
      final maxR = capRect.longestSide * 1.1;
      final r = maxR * Curves.easeOutCubic.transform(ripple);
      final center = touch.translate(0, dy);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: 0.45 * (1 - ripple)),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.85, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: math.max(r, 0.01))),
      );
    }

    // Reflexo especular no topo (dá volume ao plástico).
    canvas.drawRect(
      Rect.fromLTWH(capRect.left, capRect.top, capRect.width, capRect.height * 0.45),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0)],
        ).createShader(capRect),
    );
    canvas.restore();

    // 6. Borda neon: traço desfocado (brilho) + traço nítido.
    final borderAlpha = (0.35 + 0.65 * g1).clamp(0.0, 1.0);
    canvas.drawRRect(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 2 * g
        ..color = color.withValues(alpha: borderAlpha * 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 3 * g),
    );
    canvas.drawRRect(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + 1.0 * press
        ..color = color.withValues(alpha: borderAlpha),
    );

    // 7. Anel de progresso das teclas que exigem segurar.
    if (hold > 0) {
      final path = Path()..addRRect(cap.deflate(3));
      for (final PathMetric m in path.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * hold),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = Palette.textStrong.withValues(alpha: 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(KeycapPainter old) =>
      old.color != color ||
      old.glow != glow ||
      old.press != press ||
      old.ripple != ripple ||
      old.touch != touch ||
      old.hold != hold;
}
