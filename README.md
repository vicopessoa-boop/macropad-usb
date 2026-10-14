# Macropad USB

Macropad mecânico virtual estilo Stream Deck: o **celular** vira um teclado de atalhos com keycaps
RGB e feedback háptico, e o **desktop** recebe os comandos pelo **cabo USB** para simular teclas,
colar snippets ou rodar comandos de terminal. Não depende de Wi-Fi.

```
┌──────────────── Celular (Flutter) ───────────────┐         ┌────────────── Desktop (Go) ───────────────┐
│ NeonKey (CustomPainter + haptics)                │         │ cmd/main.go                               │
│   └─ MacropadConnection ── ws://127.0.0.1:8080 ──┼── USB ──┼─▶ server  (WebSocket /ws, 127.0.0.1:8080)  │
│                                                  │  adb    │     ├─ simulator  KEY_COMBO / PASTE / TYPE │
│ LayerBar (VS Code │ Git/Shell │ Debug)           │ reverse │     └─ runner     EXEC_SHELL (assíncrono)  │
└──────────────────────────────────────────────────┘         │ adb  (reaplica o reverse a cada replug)   │
                                                             └───────────────────────────────────────────┘
```

## Estrutura

```
macropad-usb/
├── desktop-server/
│   ├── cmd/main.go                 # entrypoint: flags, adb, servidor HTTP/WS
│   ├── internal/adb/               # descoberta do adb + watcher do "adb reverse"
│   ├── internal/simulator/         # teclado/clipboard: xdotool·wtype / osascript / user32 / robotgo
│   ├── internal/runner/            # execução assíncrona de shell (timeout, concorrência, anti-duplo-clique)
│   ├── internal/server/            # WebSocket, fila de input, STATUS_UPDATE
│   ├── internal/protocol/          # mensagens JSON
│   ├── internal/config/            # config.json
│   ├── scripts/adb-reverse.sh|ps1  # túnel USB manual (debug / -no-adb)
│   └── config.json                 # porta, segurança e layers enviadas ao app
└── mobile-client/
    ├── lib/main.dart
    ├── lib/ui/macropad_screen.dart
    ├── lib/ui/components/          # neon_key, layer_bar, connection_badge, settings_sheet
    ├── lib/services/               # macropad_connection, settings_store, default_layers
    └── lib/models/                 # layer, macro_key, macro_action, status_update
```

## Como rodar

### 1. Desktop

Requisitos: Go 1.24+, [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`) e:

| Sistema | Simulação de teclado (backend padrão, sem cgo) |
|---|---|
| Linux X11 | `xdotool` + `xclip` (ou `xsel`) |
| Linux Wayland | `wtype` + `wl-clipboard` |
| macOS | nada a instalar; dar permissão de **Acessibilidade** ao terminal |
| Windows | PowerShell (nativo). Para menor latência prefira o build `robotgo` |

```bash
cd macropad-usb/desktop-server
go run ./cmd                      # usa ./config.json
go run ./cmd -dry-run             # só registra as ações no log (teste do protocolo)
go build -o macropad ./cmd        # binário
go build -tags robotgo -o macropad ./cmd   # backend robotgo (cgo; ver requisitos do robotgo)
```

Flags: `-config caminho`, `-port 9000`, `-no-adb` (quando usar USB tethering), `-dry-run`.

Ao subir, o daemon executa `adb reverse tcp:8080 tcp:8080` para cada aparelho autorizado e
**reaplica sozinho** quando o cabo é replugado. `GET http://127.0.0.1:8080/health` mostra o estado.

### 2. Celular

1. Ative **Opções do desenvolvedor → Depuração USB**, conecte o cabo e aceite a chave RSA.
2. Instale e abra o app:

```bash
cd macropad-usb/mobile-client
flutter pub get
flutter run            # ou: flutter build apk --release && adb install build/app/outputs/flutter-apk/app-release.apk
```

O app conecta em `ws://127.0.0.1:8080/ws` (que o `adb reverse` leva até o desktop), reconecta
sozinho em ~300 ms quando o cabo volta e mostra a latência medida no topo.

**Fallback (USB tethering):** ative o tethering USB no celular, rode o daemon com
`listen_addr` = IP do desktop na interface do tethering (ex.: `192.168.42.x`) **e um `token`**,
e no app toque no indicador de conexão para trocar host/token.

> iOS: não há `adb reverse`. Use o fallback por rede (tethering/hotspot) com token.

## Protocolo (JSON sobre WebSocket)

Celular → desktop:

```jsonc
{ "type": "HELLO", "token": "opcional" }                    // obrigatório só se config.token estiver definido
{ "type": "PING", "ts": 1712345678901 }                     // responde PONG com o mesmo ts
{ "type": "ACTION", "action_type": "KEY_COMBO",     "button_id": "btn_palette", "payload": { "keys": ["ctrl", "shift", "p"] } }
{ "type": "ACTION", "action_type": "PASTE_SNIPPET", "button_id": "btn_log",     "payload": { "text": "console.log('DEBUG:', $0);", "indent": true } }
{ "type": "ACTION", "action_type": "EXEC_SHELL",    "button_id": "btn_pull",    "payload": { "command": "git pull origin main", "cwd": "~/proj", "timeout_sec": 120 } }
{ "type": "ACTION", "action_type": "TYPE_TEXT",     "button_id": "btn_sig",     "payload": { "text": "Abraços,\nEquipe" } }
```

Desktop → celular:

```jsonc
{ "type": "HELLO", "server": "macropad-usb", "version": "0.1.0", "backend": "xdotool" }
{ "type": "LAYOUT", "layers": [ ... ] }                     // layers do config.json; o app passa a usá-las
{ "type": "STATUS_UPDATE", "button_id": "btn_docker_build", "status": "SUCCESS", "color_hex": "#00FF66", "message": "saída…", "elapsed_ms": 8421 }
{ "type": "ERROR", "message": "token inválido" }
```

- `button_id` e `request_id` são opcionais em `ACTION` e voltam no `STATUS_UPDATE`.
- `status`: `RUNNING` (#FFB000) → `SUCCESS` (#00FF66) | `ERROR` (#FF2D55). Comandos de shell
  sempre emitem `RUNNING` antes do resultado; status de shell vão para todos os celulares conectados.
- **Teclas:** `ctrl shift alt cmd` (aliases `control`, `super`, `win`, `option`…), `enter tab space
  escape backspace delete insert home end pageup pagedown up down left right f1…f24 volumeup
  volumedown mute playpause` ou um caractere. **`mod`** = Cmd no macOS e Ctrl no Linux/Windows,
  para um mesmo layout servir aos três sistemas.
- **Snippets:** colados via área de transferência (Ctrl/Cmd+V), que é restaurada em seguida.
  `indent: true` remove a indentação comum para o editor reindentar no ponto do cursor.
  `$0` marca onde o cursor deve ficar depois de colar.
- Ações de teclado passam por uma fila única (ordem garantida); shells rodam em paralelo
  (`max_concurrent`) e o mesmo botão não dispara de novo enquanto o comando anterior roda.

## Layers / perfis

As layers ficam no `desktop-server/config.json` e são enviadas ao app na conexão — edite no
desktop e reconecte, sem recompilar o app (o app tem um layout padrão equivalente para uso offline).

```jsonc
{ "id": "git", "name": "Git / Shell", "color": "#7CFF00", "columns": 3, "keys": [
  { "id": "btn_git_push", "label": "Push", "icon": "up", "color": "#FF6B00", "confirm": true,
    "action": { "action_type": "EXEC_SHELL", "payload": { "command": "git push", "cwd": "~/meu-projeto" } } }
] }
```

- `columns`: 3 → grade 3×3, 4 → 4×3 etc.
- `confirm: true`: precisa **segurar ~0,6 s** (anel de progresso na borda) — use em push/deploy.
- `icon`: `search file terminal comment format edit code save info up down left right next build
  play stop check clear dot volup voldown mute git bug rocket`.

## Iluminação e feedback (app)

- **Idle:** pulso sutil de brilho com fase diagonal por tecla (uma "onda" percorre o teclado).
- **Press down:** a ação é enviada **no toque** (não no soltar); o keycap afunda 4 px, o brilho
  dispara, um ripple de luz nasce no ponto tocado e `HapticFeedback.heavyImpact`.
- **Release:** a luz dissipa em ~0,5 s + `HapticFeedback.lightImpact`.
- **Status:** `RUNNING` pulsa em âmbar; `SUCCESS`/`ERROR` acendem na cor do status e esmaecem;
  erro vibra. A saída do último comando aparece no console inferior.
- Bloom feito com `MaskFilter.blur` + gradientes no `CustomPainter` (roda em qualquer GPU);
  um `FragmentShader` pode substituir o bloom no futuro sem mudar a API do `NeonKey`.

## Segurança

`EXEC_SHELL` executa comandos arbitrários no desktop, então:

- O daemon escuta só em **127.0.0.1** por padrão; via `adb reverse` só o celular autorizado por
  Depuração USB alcança a porta.
- Conexões com cabeçalho `Origin` (navegadores) são **recusadas**: uma página web aberta no desktop
  não consegue falar com `ws://localhost:8080`.
- `token` (ou env `MACROPAD_TOKEN`) exige `HELLO` autenticado — **obrigatório** se mudar `listen_addr`.
- `shell.enabled: false` desliga shell; `shell.allowlist` restringe aos comandos listados
  (argumentos extras são aceitos, metacaracteres como `; && | $()` não).

## Testes

```bash
cd desktop-server && go test ./...     # protocolo, allowlist, normalização de teclas, WS ponta a ponta
cd mobile-client  && flutter test      # modelos, conexão WS contra servidor local, widget da tela
```

## Solução de problemas

| Sintoma | Causa provável |
|---|---|
| App fica em "Desconectado" | daemon parado, ou `adb devices` mostra `unauthorized` (aceite a chave no celular) |
| `adb: túnel ativo` não aparece no log | adb fora do PATH → defina `adb.path` no `config.json` |
| Teclas não fazem nada no Linux | falta `xdotool`/`wtype`; no Wayland o compositor precisa suportar virtual-keyboard |
| Teclas não fazem nada no macOS | conceda Acessibilidade ao Terminal/iTerm em Ajustes → Privacidade |
| Snippet cola texto antigo | o app de destino leu a área de transferência tarde: use `restore_clipboard: false` |
| `git pull` falha com "not a git repository" | defina `cwd` na tecla ou `shell.default_cwd` |
