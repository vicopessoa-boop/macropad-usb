import 'package:flutter/material.dart';

import 'macro_key.dart';

/// Perfil/layer: um conjunto de teclas com cor de destaque própria.
class Layer {
  final String id;
  final String name;
  final Color color;
  final int columns;
  final List<MacroKey> keys;

  const Layer({required this.id, required this.name, required this.color, required this.keys, this.columns = 3});

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        color: parseHexColor(json['color'] as String?) ?? const Color(0xFF00E5FF),
        columns: ((json['columns'] as num?)?.toInt() ?? 3).clamp(1, 6),
        keys: [
          for (final k in (json['keys'] as List? ?? const [])) MacroKey.fromJson(Map<String, dynamic>.from(k as Map))
        ],
      );

  static List<Layer> listFromJson(List<dynamic> json) => [
        for (final l in json) Layer.fromJson(Map<String, dynamic>.from(l as Map)),
      ];
}
