// Package protocol define as mensagens JSON trocadas entre o app móvel e o daemon.
package protocol

import "encoding/json"

// Tipos de mensagem (campo "type").
const (
	TypeAction       = "ACTION"
	TypeStatusUpdate = "STATUS_UPDATE"
	TypeLayout       = "LAYOUT"
	TypeHello        = "HELLO"
	TypePing         = "PING"
	TypePong         = "PONG"
	TypeError        = "ERROR"
)

// Tipos de ação (campo "action_type").
const (
	ActionKeyCombo     = "KEY_COMBO"
	ActionPasteSnippet = "PASTE_SNIPPET"
	ActionExecShell    = "EXEC_SHELL"
	ActionTypeText     = "TYPE_TEXT"
)

// Status reportados em STATUS_UPDATE.
const (
	StatusRunning = "RUNNING"
	StatusSuccess = "SUCCESS"
	StatusError   = "ERROR"
)

// Cores padrão associadas a cada status.
var StatusColors = map[string]string{
	StatusRunning: "#FFB000",
	StatusSuccess: "#00FF66",
	StatusError:   "#FF2D55",
}

// Envelope é usado para descobrir o tipo antes de decodificar o resto.
type Envelope struct {
	Type string `json:"type"`
}

// Action é um comando vindo do celular.
//
//	{ "type": "ACTION", "action_type": "KEY_COMBO", "button_id": "btn_palette",
//	  "request_id": "a1", "payload": { "keys": ["ctrl", "shift", "p"] } }
//
// button_id e request_id são opcionais; quando presentes, voltam no STATUS_UPDATE.
type Action struct {
	Type       string          `json:"type"`
	ActionType string          `json:"action_type"`
	ButtonID   string          `json:"button_id,omitempty"`
	RequestID  string          `json:"request_id,omitempty"`
	Payload    json.RawMessage `json:"payload"`
}

// KeyComboPayload: teclas pressionadas juntas, modificadores primeiro.
type KeyComboPayload struct {
	Keys []string `json:"keys"`
}

// PasteSnippetPayload: texto colado via área de transferência.
// Se Indent for true, a indentação comum é removida para o editor reindentar.
// O marcador "$0" (opcional) indica onde o cursor deve ficar após colar.
type PasteSnippetPayload struct {
	Text   string `json:"text"`
	Indent bool   `json:"indent"`
}

// TypeTextPayload: texto digitado tecla a tecla (sem usar a área de transferência).
type TypeTextPayload struct {
	Text string `json:"text"`
}

// ExecShellPayload: comando executado de forma assíncrona no desktop.
type ExecShellPayload struct {
	Command    string `json:"command"`
	Cwd        string `json:"cwd,omitempty"`
	TimeoutSec int    `json:"timeout_sec,omitempty"`
}

// StatusUpdate é enviado ao celular para acender/colorir um botão.
type StatusUpdate struct {
	Type      string `json:"type"`
	ButtonID  string `json:"button_id,omitempty"`
	RequestID string `json:"request_id,omitempty"`
	Status    string `json:"status"`
	ColorHex  string `json:"color_hex"`
	Message   string `json:"message,omitempty"`
	ElapsedMs int64  `json:"elapsed_ms,omitempty"`
}

// NewStatus cria um STATUS_UPDATE com a cor padrão do status.
func NewStatus(a *Action, status, msg string) StatusUpdate {
	s := StatusUpdate{Type: TypeStatusUpdate, Status: status, ColorHex: StatusColors[status], Message: msg}
	if a != nil {
		s.ButtonID = a.ButtonID
		s.RequestID = a.RequestID
	}
	return s
}

// Hello é a primeira mensagem do celular. Token só é exigido se configurado.
type Hello struct {
	Type   string `json:"type"`
	Token  string `json:"token,omitempty"`
	Client string `json:"client,omitempty"`
}

// Ping/Pong para medir latência ponta a ponta.
type Ping struct {
	Type string `json:"type"`
	TS   int64  `json:"ts"`
}

// Layout envia ao celular os perfis/layers definidos no config.json do desktop.
type Layout struct {
	Type   string          `json:"type"`
	Layers json.RawMessage `json:"layers"`
}

// ErrorMsg informa erros de protocolo (JSON inválido, não autenticado...).
type ErrorMsg struct {
	Type    string `json:"type"`
	Message string `json:"message"`
}
