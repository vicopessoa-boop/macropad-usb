import 'package:flutter/material.dart';

import 'macro_action.dart';

/// Uma tecla (keycap) do macropad.
class MacroKey {
  final String id;
  final String label;
  final String? icon;

  /// Cor neon própria; se nula, usa a cor da layer.
  final Color? color;

  /// Teclas perigosas (push, deploy...) exigem segurar ~0,6 s para disparar.
  final bool confirm;
  final MacroAction action;

  const MacroKey({
    required this.id,
    required this.label,
    required this.action,
    this.icon,
    this.color,
    this.confirm = false,
  });

  factory MacroKey.fromJson(Map<String, dynamic> json) => MacroKey(
        id: json['id'] as String,
        label: json['label'] as String? ?? json['id'] as String,
        icon: json['icon'] as String?,
        color: parseHexColor(json['color'] as String?),
        confirm: json['confirm'] as bool? ?? false,
        action: MacroAction.fromJson(Map<String, dynamic>.from(json['action'] as Map)),
      );
}

/// Converte "#RRGGBB" ou "#AARRGGBB" em Color. Retorna null se inválido.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Ícones disponíveis para o campo "icon" do layout.
const Map<String, IconData> keyIcons = {
  'search': Icons.search_rounded,
  'file': Icons.insert_drive_file_outlined,
  'terminal': Icons.terminal_rounded,
  'comment': Icons.comment_outlined,
  'format': Icons.format_align_left_rounded,
  'edit': Icons.edit_outlined,
  'code': Icons.code_rounded,
  'save': Icons.save_outlined,
  'info': Icons.info_outline_rounded,
  'up': Icons.arrow_upward_rounded,
  'down': Icons.arrow_downward_rounded,
  'left': Icons.arrow_back_rounded,
  'right': Icons.arrow_forward_rounded,
  'next': Icons.redo_rounded,
  'build': Icons.build_rounded,
  'play': Icons.play_arrow_rounded,
  'stop': Icons.stop_rounded,
  'check': Icons.check_rounded,
  'clear': Icons.clear_all_rounded,
  'dot': Icons.fiber_manual_record,
  'volup': Icons.volume_up_rounded,
  'voldown': Icons.volume_down_rounded,
  'mute': Icons.volume_off_rounded,
  'git': Icons.merge_type_rounded,
  'bug': Icons.bug_report_outlined,
  'rocket': Icons.rocket_launch_outlined,
};
