// Package simulator emula teclado no desktop: atalhos, digitação e colagem de snippets.
//
// Os nomes de tecla aceitos no protocolo são normalizados para um vocabulário canônico
// (ctrl, shift, alt, cmd, enter, tab, f5, left, ...) e cada backend traduz para a
// ferramenta da plataforma (xdotool/wtype, osascript, user32 ou robotgo).
package simulator

import (
	"errors"
	"fmt"
	"log"
	"runtime"
	"strings"
	"time"
	"unicode/utf8"
)

// CursorMarker indica, dentro de um snippet, onde o cursor deve parar após colar.
const CursorMarker = "$0"

// Backend é a implementação específica da plataforma.
type Backend interface {
	Name() string
	// KeyCombo pressiona as teclas na ordem e solta na ordem inversa. Nomes canônicos.
	KeyCombo(keys []string) error
	TypeText(text string) error
	SetClipboard(text string) error
	GetClipboard() (string, error)
}

// ErrUnsupported é devolvido quando o backend não suporta uma operação.
var ErrUnsupported = errors.New("operação não suportada nesta plataforma")

type Options struct {
	DryRun           bool
	TypeDelayMs      int
	RestoreClipboard bool
}

type Simulator struct {
	b    Backend
	opts Options
}

func New(opts Options) (*Simulator, error) {
	if opts.DryRun {
		return &Simulator{b: logBackend{}, opts: opts}, nil
	}
	b, err := newPlatformBackend(opts.TypeDelayMs)
	if err != nil {
		return nil, err
	}
	return &Simulator{b: b, opts: opts}, nil
}

// NewWithBackend permite injetar um backend (testes).
func NewWithBackend(b Backend, opts Options) *Simulator { return &Simulator{b: b, opts: opts} }

func (s *Simulator) Name() string { return s.b.Name() }

func (s *Simulator) KeyCombo(keys []string) error {
	canon, err := Normalize(keys)
	if err != nil {
		return err
	}
	return s.b.KeyCombo(canon)
}

func (s *Simulator) TypeText(text string) error {
	if text == "" {
		return nil
	}
	return s.b.TypeText(text)
}

// PasteSnippet coloca o texto na área de transferência, cola com Ctrl/Cmd+V,
// posiciona o cursor no marcador $0 (se houver) e restaura a área de transferência.
func (s *Simulator) PasteSnippet(text string, indent bool) error {
	if text == "" {
		return errors.New("snippet vazio")
	}
	if indent {
		text = Dedent(text)
	}
	text, back := splitCursor(text)

	var previous string
	var hadPrevious bool
	if s.opts.RestoreClipboard {
		if p, err := s.b.GetClipboard(); err == nil {
			previous, hadPrevious = p, true
		}
	}
	if err := s.b.SetClipboard(text); err != nil {
		return fmt.Errorf("área de transferência: %w", err)
	}
	if err := s.b.KeyCombo([]string{PrimaryModifier(), "v"}); err != nil {
		return err
	}
	for i := 0; i < back; i++ {
		if err := s.b.KeyCombo([]string{"left"}); err != nil {
			return err
		}
	}
	if hadPrevious {
		// O app de destino lê a área de transferência de forma assíncrona; espere antes de restaurar.
		time.Sleep(150 * time.Millisecond)
		if err := s.b.SetClipboard(previous); err != nil {
			log.Printf("simulator: falha ao restaurar área de transferência: %v", err)
		}
	}
	return nil
}

// splitCursor remove o primeiro $0 e devolve quantas setas para a esquerda são
// necessárias para chegar até ele (cada quebra de linha conta como uma posição).
func splitCursor(text string) (string, int) {
	i := strings.Index(text, CursorMarker)
	if i < 0 {
		return text, 0
	}
	after := strings.ReplaceAll(text[i+len(CursorMarker):], "\r\n", "\n")
	return text[:i] + text[i+len(CursorMarker):], utf8.RuneCountInString(after)
}

// Dedent remove a indentação comum a todas as linhas não vazias, para que o editor
// reaplique a indentação do ponto onde o snippet é colado.
func Dedent(text string) string {
	lines := strings.Split(text, "\n")
	common := -1
	var prefix string
	for _, l := range lines {
		if strings.TrimSpace(l) == "" {
			continue
		}
		lead := l[:len(l)-len(strings.TrimLeft(l, " \t"))]
		if common < 0 {
			common, prefix = len(lead), lead
			continue
		}
		n := 0
		for n < len(lead) && n < len(prefix) && lead[n] == prefix[n] {
			n++
		}
		if n < common {
			common, prefix = n, prefix[:n]
		}
	}
	if common <= 0 {
		return text
	}
	for i, l := range lines {
		if len(l) >= common {
			lines[i] = l[common:]
		} else {
			lines[i] = strings.TrimLeft(l, " \t")
		}
	}
	return strings.Join(lines, "\n")
}

// PrimaryModifier é Cmd no macOS e Ctrl nas demais plataformas.
func PrimaryModifier() string {
	if runtime.GOOS == "darwin" {
		return "cmd"
	}
	return "ctrl"
}

var aliases = map[string]string{
	"control": "ctrl", "ctl": "ctrl",
	"command": "cmd", "super": "cmd", "win": "cmd", "windows": "cmd", "meta": "cmd",
	"option": "alt", "opt": "alt", "altgr": "alt",
	"return": "enter", "esc": "escape",
	"del": "delete", "bksp": "backspace",
	"pgup": "pageup", "page_up": "pageup", "prior": "pageup",
	"pgdn": "pagedown", "page_down": "pagedown", "next": "pagedown",
	"ins":     "insert",
	"arrowup": "up", "arrowdown": "down", "arrowleft": "left", "arrowright": "right",
	"volume_up": "volumeup", "volume_down": "volumedown", "volume_mute": "mute",
	"play": "playpause", "play_pause": "playpause",
	"plus": "+", "minus": "-", "comma": ",", "period": ".", "slash": "/",
}

var named = map[string]bool{
	"ctrl": true, "shift": true, "alt": true, "cmd": true,
	"enter": true, "tab": true, "space": true, "escape": true, "backspace": true, "delete": true,
	"up": true, "down": true, "left": true, "right": true,
	"home": true, "end": true, "pageup": true, "pagedown": true, "insert": true,
	"volumeup": true, "volumedown": true, "mute": true, "playpause": true,
}

// IsModifier indica se a tecla canônica é um modificador.
func IsModifier(k string) bool { return k == "ctrl" || k == "shift" || k == "alt" || k == "cmd" }

// Normalize converte nomes livres em nomes canônicos. "mod" vira Cmd no macOS e Ctrl
// no resto, permitindo um mesmo layout para todos os sistemas.
func Normalize(keys []string) ([]string, error) {
	if len(keys) == 0 {
		return nil, errors.New("nenhuma tecla informada")
	}
	out := make([]string, 0, len(keys))
	for _, raw := range keys {
		k := strings.TrimSpace(raw)
		if utf8.RuneCountInString(k) != 1 {
			k = strings.ToLower(k)
		}
		if a, ok := aliases[k]; ok {
			k = a
		}
		if k == "mod" {
			k = PrimaryModifier()
		}
		switch {
		case named[k]:
		case isFunctionKey(k):
		case utf8.RuneCountInString(k) == 1:
			k = strings.ToLower(k)
		default:
			return nil, fmt.Errorf("tecla desconhecida: %q", raw)
		}
		out = append(out, k)
	}
	return out, nil
}

func isFunctionKey(k string) bool {
	var n int
	if _, err := fmt.Sscanf(k, "f%d", &n); err != nil {
		return false
	}
	return fmt.Sprintf("f%d", n) == k && n >= 1 && n <= 24
}

// logBackend apenas registra as ações (modo -dry-run, útil para testar o protocolo).
type logBackend struct{}

func (logBackend) Name() string { return "dry-run" }
func (logBackend) KeyCombo(keys []string) error {
	log.Printf("[dry-run] KEY_COMBO %v", keys)
	return nil
}
func (logBackend) TypeText(t string) error       { log.Printf("[dry-run] TYPE %q", t); return nil }
func (logBackend) SetClipboard(t string) error   { log.Printf("[dry-run] CLIPBOARD %q", t); return nil }
func (logBackend) GetClipboard() (string, error) { return "", ErrUnsupported }
