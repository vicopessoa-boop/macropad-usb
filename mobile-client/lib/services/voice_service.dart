import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Ditado pelo microfone do celular (reconhecimento de voz do Android).
/// O texto final é enviado ao desktop e colado na janela em foco (ex.: Claude Code).
class VoiceService {
  final SpeechToText _stt = SpeechToText();
  bool? _ready;

  bool get isListening => _stt.isListening;

  /// Pede permissão do microfone na primeira vez. false = sem permissão/serviço.
  Future<bool> _ensureReady(void Function(String) onError) async {
    if (_ready == true) return true;
    _ready = await _stt.initialize(onError: (e) => onError(e.errorMsg));
    return _ready!;
  }

  /// Começa a ouvir. [onPartial] recebe o texto parcial; [onFinal] o texto final
  /// (vazio se nada foi reconhecido). Quem encerra é [stop] (ao soltar a tecla).
  Future<bool> start({
    required String localeId,
    required void Function(String) onPartial,
    required void Function(String) onFinal,
    required void Function(String) onError,
  }) async {
    if (!await _ensureReady(onError)) return false;
    var done = false;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        if (done) return;
        if (r.finalResult) {
          done = true;
          onFinal(r.recognizedWords.trim());
        } else {
          onPartial(r.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        autoPunctuation: true,
        pauseFor: const Duration(seconds: 30),
        listenFor: const Duration(seconds: 90),
      ),
    );
    return true;
  }

  /// Para de ouvir; o reconhecimento entrega o resultado final em seguida.
  Future<void> stop() => _stt.stop();
}
