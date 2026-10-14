import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/layer.dart';

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
                color: active ? layer.color.withValues(alpha: 0.14) : const Color(0xFF12141A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: active ? layer.color : const Color(0xFF2A2E38),
                  width: active ? 1.5 : 1,
                ),
                boxShadow: active
                    ? [BoxShadow(color: layer.color.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -2)]
                    : const [],
              ),
              child: Text(
                '${i + 1}  ${layer.name}',
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF8A919E),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                  shadows: active ? [Shadow(color: layer.color, blurRadius: 10)] : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
