import 'package:flutter/material.dart';

import 'macro_key.dart';

enum KeyStatus { running, success, error }

/// STATUS_UPDATE vindo do desktop: { "type": "STATUS_UPDATE", "button_id": ...,
/// "status": "SUCCESS", "color_hex": "#00FF66", "message": ..., "elapsed_ms": ... }
class StatusUpdate {
  final String buttonId;
  final KeyStatus status;
  final Color color;
  final String? message;
  final int? elapsedMs;
  final DateTime receivedAt;

  StatusUpdate({
    required this.buttonId,
    required this.status,
    required this.color,
    this.message,
    this.elapsedMs,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  static StatusUpdate? fromJson(Map<String, dynamic> json) {
    final id = json['button_id'] as String?;
    final status = switch (json['status']) {
      'RUNNING' => KeyStatus.running,
      'SUCCESS' => KeyStatus.success,
      'ERROR' => KeyStatus.error,
      _ => null,
    };
    if (id == null || status == null) return null;
    return StatusUpdate(
      buttonId: id,
      status: status,
      color: parseHexColor(json['color_hex'] as String?) ?? defaultColor(status),
      message: json['message'] as String?,
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt(),
    );
  }

  static Color defaultColor(KeyStatus s) => switch (s) {
        KeyStatus.running => const Color(0xFFFFB000),
        KeyStatus.success => const Color(0xFF00FF66),
        KeyStatus.error => const Color(0xFFFF2D55),
      };
}
