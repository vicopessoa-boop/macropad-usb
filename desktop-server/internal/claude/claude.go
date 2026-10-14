// Package claude acompanha o estado das sessões do Claude Code a partir dos hooks.
//
// Cada hook do Claude Code (UserPromptSubmit, PostToolUse, Notification, Stop,
// SessionStart, SessionEnd) envia seu JSON de entrada para POST /claude; aqui ele é
// traduzido num estado simples que o celular mostra como uma luz colorida.
package claude

import (
	"encoding/json"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Estados exibidos no visor.
const (
	StateIdle      = "idle"      // sessão aberta, sem tarefa
	StateWorking   = "working"   // trabalhando (azul)
	StateDone      = "done"      // pronto (verde)
	StateWaiting   = "waiting"   // aguardando autorização (amarelo)
	StateAttention = "attention" // erro ou precisa de atenção (vermelho)
)

// HookInput são os campos do JSON que o Claude Code envia aos hooks que usamos.
type HookInput struct {
	SessionID        string `json:"session_id"`
	Cwd              string `json:"cwd"`
	HookEventName    string `json:"hook_event_name"`
	Message          string `json:"message"`
	NotificationType string `json:"notification_type"`
	Error            string `json:"error"` // StopFailure: rate_limit, overloaded...
}

type Session struct {
	ID        string `json:"id"`
	Project   string `json:"project"`
	State     string `json:"state"`
	Message   string `json:"message,omitempty"`
	UpdatedMs int64  `json:"updated_ms"`
}

// Sessões sem notícia há mais tempo que isso somem do visor.
const staleAfter = 3 * time.Hour

type Tracker struct {
	mu       sync.Mutex
	sessions map[string]*Session
	now      func() time.Time
}

func NewTracker() *Tracker {
	return &Tracker{sessions: map[string]*Session{}, now: time.Now}
}

// stateFor traduz o evento do hook. ok=false: evento ignorado. remove=true: sessão encerrada.
func stateFor(in HookInput) (state, msg string, ok, remove bool) {
	switch in.HookEventName {
	case "UserPromptSubmit", "PreToolUse", "PostToolUse":
		return StateWorking, "Trabalhando…", true, false
	case "PermissionRequest":
		return StateWaiting, "Aguardando autorização", true, false
	case "Stop":
		return StateDone, "Pronto", true, false
	case "StopFailure":
		msg := "Erro"
		if in.Error != "" {
			msg = "Erro: " + in.Error
		}
		return StateAttention, msg, true, false
	case "SessionStart":
		return StateIdle, "Sessão aberta", true, false
	case "SessionEnd":
		return "", "", true, true
	case "Notification":
		switch strings.ToLower(in.NotificationType) {
		case "permission_prompt":
			return StateWaiting, "Aguardando autorização", true, false
		case "idle_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
			return StateAttention, "Precisa de atenção", true, false
		case "":
			// Versões antigas não mandam o tipo: deduz pelo texto.
			if strings.Contains(strings.ToLower(in.Message), "permission") {
				return StateWaiting, "Aguardando autorização", true, false
			}
			return StateAttention, "Precisa de atenção", true, false
		}
		return "", "", false, false // auth_success, *_complete etc.: não mudam o visor
	}
	return "", "", false, false
}

// Apply registra um evento. Retorna true se o visor mudou.
func (t *Tracker) Apply(in HookInput) bool {
	state, msg, ok, remove := stateFor(in)
	if !ok {
		return false
	}
	id := in.SessionID
	if id == "" {
		id = in.Cwd
	}
	if id == "" {
		id = "claude"
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if remove {
		_, existed := t.sessions[id]
		delete(t.sessions, id)
		return existed
	}
	s, exists := t.sessions[id]
	if !exists {
		s = &Session{ID: id}
		t.sessions[id] = s
	}
	if in.Cwd != "" {
		s.Project = filepath.Base(filepath.Clean(strings.ReplaceAll(in.Cwd, `\`, "/")))
	}
	if s.Project == "" || s.Project == "." || s.Project == "/" {
		s.Project = "Claude"
	}
	changed := !exists || s.State != state || s.Message != msg
	s.State, s.Message = state, msg
	s.UpdatedMs = t.now().UnixMilli()
	return changed
}

// Snapshot devolve as sessões ativas, as mais recentes primeiro.
func (t *Tracker) Snapshot() []Session {
	t.mu.Lock()
	defer t.mu.Unlock()
	cutoff := t.now().Add(-staleAfter).UnixMilli()
	out := make([]Session, 0, len(t.sessions))
	for id, s := range t.sessions {
		if s.UpdatedMs < cutoff {
			delete(t.sessions, id)
			continue
		}
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].UpdatedMs > out[j].UpdatedMs })
	return out
}

// Decode lê o JSON do hook; corpo vazio ou inválido vira um HookInput vazio.
func Decode(body []byte) HookInput {
	var in HookInput
	_ = json.Unmarshal(body, &in)
	return in
}
