#!/usr/bin/env bash
# Cria o túnel USB: localhost:PORT no celular -> localhost:PORT no desktop.
# O daemon já faz isso sozinho (e reaplica ao replugar); use este script para
# depurar ou quando rodar o servidor com -no-adb.
#
#   ./scripts/adb-reverse.sh            # porta 8080, todos os aparelhos
#   ./scripts/adb-reverse.sh 9000       # outra porta
#   ./scripts/adb-reverse.sh --watch    # fica reaplicando a cada 3s
set -euo pipefail

PORT=8080
WATCH=0
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=1 ;;
    ''|*[!0-9]*) echo "uso: $0 [PORTA] [--watch]" >&2; exit 2 ;;
    *) PORT="$arg" ;;
  esac
done

ADB="${ADB:-$(command -v adb || true)}"
if [[ -z "$ADB" && -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  ADB="${ANDROID_HOME:-$ANDROID_SDK_ROOT}/platform-tools/adb"
fi
[[ -x "$ADB" ]] || { echo "adb não encontrado. Instale o Android platform-tools." >&2; exit 1; }

apply() {
  local found=0
  while read -r serial state; do
    [[ "$state" == "device" ]] || continue
    found=1
    if ! "$ADB" -s "$serial" reverse --list 2>/dev/null | grep -q "tcp:$PORT tcp:$PORT"; then
      "$ADB" -s "$serial" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
      echo "✔ [$serial] celular localhost:$PORT -> desktop localhost:$PORT"
    fi
  done < <("$ADB" devices | tail -n +2)
  if [[ $found -eq 0 ]]; then
    echo "Nenhum aparelho autorizado. Ative a Depuração USB e aceite a chave RSA no celular." >&2
    return 1
  fi
}

"$ADB" start-server >/dev/null
if [[ $WATCH -eq 1 ]]; then
  echo "Observando aparelhos (Ctrl+C para sair)..."
  while true; do apply || true; sleep 3; done
else
  apply
fi
