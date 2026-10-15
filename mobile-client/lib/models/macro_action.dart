/// Ação enviada ao desktop quando uma tecla é pressionada.
class MacroAction {
  static const keyCombo = 'KEY_COMBO';
  static const pasteSnippet = 'PASTE_SNIPPET';
  static const execShell = 'EXEC_SHELL';
  static const typeText = 'TYPE_TEXT';

  /// Ditado pelo microfone do celular; tratado no app (não vai ao desktop como está).
  static const voice = 'VOICE';

  final String actionType;
  final Map<String, dynamic> payload;

  const MacroAction(this.actionType, this.payload);

  // Construtores de conveniência para os layouts padrão.
  static MacroAction combo(List<String> keys) => MacroAction(keyCombo, {'keys': keys});
  static MacroAction snippet(String text, {bool indent = true}) =>
      MacroAction(pasteSnippet, {'text': text, 'indent': indent});
  static MacroAction shell(String command, {String? cwd, int? timeoutSec}) => MacroAction(execShell, {
        'command': command,
        if (cwd != null) 'cwd': cwd,
        if (timeoutSec != null) 'timeout_sec': timeoutSec,
      });

  factory MacroAction.fromJson(Map<String, dynamic> json) =>
      MacroAction(json['action_type'] as String, Map<String, dynamic>.from(json['payload'] as Map? ?? const {}));

  /// Mensagem do protocolo: { "type": "ACTION", "action_type": ..., "payload": ... }
  Map<String, dynamic> toMessage({required String buttonId, required String requestId}) => {
        'type': 'ACTION',
        'action_type': actionType,
        'button_id': buttonId,
        'request_id': requestId,
        'payload': payload,
      };

  bool get isShell => actionType == execShell;
  bool get isVoice => actionType == voice;
}
