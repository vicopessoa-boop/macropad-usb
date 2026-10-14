import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/layer.dart';
import '../palette.dart';

/// Barra de perfis (VS Code, Git/Shell, Debug...). A layer ativa acende na sua cor.
class LayerBar extends StatelessWidget {
  final List<Layer> layers;
  final int current;
  final ValueChanged<int> onSelect;

  const LayerBar({super.key, required this.layers, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: layers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final layer = layers[i];
          final active = i == current;
          return GestureDetector(
            onTap: () {
              if (i == current) return;
              HapticFeedback.selectionClick();
              onSelect(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? layer.color.withValues(alpha: 0.14) : Palette.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: active ? layer.color : Palette.border, width: active ? 1.5 : 1),
                boxShadow: active
                    ? [BoxShadow(color: layer.color.withValues(alpha: 0.30), blurRadius: 12, spreadRadius: -2)]
                    : const [],
              ),
              child: Text(
                '${i + 1}  ${layer.name}',
                style: TextStyle(
                  color: active ? Palette.textStrong : Palette.textMuted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                  shadows: null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
