import 'package:flutter/material.dart';

/// Estado de uma sessão do Claude Code, recebido do desktop em CLAUDE_STATUS.
enum ClaudeState { idle, working, done, waiting, attention }

class ClaudeSession {
  final String id;
  final String project;
  final ClaudeState state;
  final String? message;
  final int updatedMs;

  const ClaudeSession({
    required this.id,
    required this.project,
    required this.state,
    required this.updatedMs,
    this.message,
  });

  factory ClaudeSession.fromJson(Map<String, dynamic> json) => ClaudeSession(
        id: json['id'] as String? ?? '',
        project: json['project'] as String? ?? 'Claude',
        state: switch (json['state']) {
          'working' => ClaudeState.working,
          'done' => ClaudeState.done,
          'waiting' => ClaudeState.waiting,
          'attention' => ClaudeState.attention,
          _ => ClaudeState.idle,
        },
        message: json['message'] as String?,
        updatedMs: (json['updated_ms'] as num?)?.toInt() ?? 0,
      );

  Color get color => switch (state) {
        ClaudeState.working => const Color(0xFF1E6BFF),
        ClaudeState.done => const Color(0xFF00A859),
        ClaudeState.waiting => const Color(0xFFF2B600),
        ClaudeState.attention => const Color(0xFFE5243F),
        ClaudeState.idle => const Color(0xFF9AA1AC),
      };

  String get label => switch (state) {
        ClaudeState.working => 'Trabalhando…',
        ClaudeState.done => 'Pronto',
        ClaudeState.waiting => 'Aguardando autorização',
        ClaudeState.attention => message?.isNotEmpty == true ? message! : 'Precisa de atenção',
        ClaudeState.idle => 'Sessão aberta',
      };
}
