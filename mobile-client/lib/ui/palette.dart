import 'package:flutter/material.dart';

/// Cores do visual claro (fundo branco). As cores de cada layer vêm do layout;
/// aqui ficam só as superfícies e textos neutros.
abstract final class Palette {
  static const background = Color(0xFFF6F7FA);
  static const surface = Colors.white;
  static const border = Color(0xFFDDE1E8);
  static const textStrong = Color(0xFF1A1D24);
  static const text = Color(0xFF3A404C);
  static const textMuted = Color(0xFF6B7280);
  static const textDisabled = Color(0xFFA3A9B4);

  // Keycap
  static const capTop = Colors.white;
  static const capBottom = Color(0xFFECEFF4);
  static const capSkirt = Color(0xFFCDD3DD);

  // Cores das layers padrão: VS Code, Git/Shell, Navegação/Debug.
  static const blue = Color(0xFF1E6BFF);
  static const green = Color(0xFF00A859);
  static const yellow = Color(0xFFF2B600);
}
