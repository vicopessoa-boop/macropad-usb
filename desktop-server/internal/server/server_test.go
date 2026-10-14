package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/config"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/runner"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/simulator"
)

type recBackend struct {
	mu     sync.Mutex
	combos [][]string
}

func (r *recBackend) Name() string { return "rec" }
func (r *recBackend) KeyCombo(k []string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.combos = append(r.combos, k)
	return nil
}
func (r *recBackend) TypeText(string) error         { return nil }
func (r *recBackend) SetClipboard(string) error     { return nil }
func (r *recBackend) GetClipboard() (string, error) { return "", simulator.ErrUnsupported }

func setup(t *testing.T, cfg config.Config) (*httptest.Server, *recBackend) {
	t.Helper()
	rb := &recBackend{}
	sim := simulator.NewWithBackend(rb, simulator.Options{})
	srv := New(cfg, sim, runner.New("", 10, 2))
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts, rb
}

func dial(t *testing.T, ts *httptest.Server, h http.Header) *websocket.Conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(ts.URL, "http") + "/ws"
	c, _, err := websocket.DefaultDialer.Dial(url, h)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

func readUntil(t *testing.T, c *websocket.Conn, match func(map[string]any) bool) map[string]any {
	t.Helper()
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	for {
		var m map[string]any
		if err := c.ReadJSON(&m); err != nil {
			t.Fatal(err)
		}
		if match(m) {
			return m
		}
	}
}

func TestKeyComboAndShell(t *testing.T) {
	cfg := config.Default()
	cfg.Layers = json.RawMessage(`[{"id":"x","keys":[]}]`)
	ts, rb := setup(t, cfg)
	c := dial(t, ts, nil)

	readUntil(t, c, func(m map[string]any) bool { return m["type"] == "LAYOUT" })

	c.WriteJSON(map[string]any{"type": "ACTION", "action_type": "KEY_COMBO", "button_id": "b1",
		"payload": map[string]any{"keys": []string{"ctrl", "shift", "p"}}})
	m := readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "b1" })
	if m["status"] != "SUCCESS" {
		t.Fatalf("status %v", m)
	}
	if len(rb.combos) != 1 || strings.Join(rb.combos[0], "+") != "ctrl+shift+p" {
		t.Fatalf("combos %v", rb.combos)
	}

	c.WriteJSON(map[string]any{"type": "ACTION", "action_type": "EXEC_SHELL", "button_id": "sh",
		"payload": map[string]any{"command": "echo ola"}})
	m = readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "sh" })
	if m["status"] != "RUNNING" {
		t.Fatalf("esperava RUNNING primeiro: %v", m)
	}
	m = readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "sh" })
	if m["status"] != "SUCCESS" || m["color_hex"] != "#00FF66" || !strings.Contains(m["message"].(string), "ola") {
		t.Fatalf("status %v", m)
	}

	c.WriteJSON(map[string]any{"type": "ACTION", "action_type": "EXEC_SHELL", "button_id": "bad",
		"payload": map[string]any{"command": "exit 3"}})
	readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "bad" && m["status"] == "RUNNING" })
	m = readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "bad" })
	if m["status"] != "ERROR" {
		t.Fatalf("status %v", m)
	}

	c.WriteJSON(map[string]any{"type": "PING", "ts": 42})
	m = readUntil(t, c, func(m map[string]any) bool { return m["type"] == "PONG" })
	if m["ts"].(float64) != 42 {
		t.Fatalf("pong %v", m)
	}
}

func TestTokenRequired(t *testing.T) {
	cfg := config.Default()
	cfg.Token = "segredo"
	ts, _ := setup(t, cfg)

	bad := dial(t, ts, nil)
	bad.WriteJSON(map[string]any{"type": "HELLO", "token": "errado"})
	m := readUntil(t, bad, func(m map[string]any) bool { return true })
	if m["type"] != "ERROR" {
		t.Fatalf("esperava ERROR: %v", m)
	}

	ok := dial(t, ts, nil)
	ok.WriteJSON(map[string]any{"type": "HELLO", "token": "segredo"})
	m = readUntil(t, ok, func(m map[string]any) bool { return true })
	if m["type"] != "HELLO" {
		t.Fatalf("esperava HELLO: %v", m)
	}
}

func TestBrowserOriginRejected(t *testing.T) {
	ts, _ := setup(t, config.Default())
	url := "ws" + strings.TrimPrefix(ts.URL, "http") + "/ws"
	_, resp, err := websocket.DefaultDialer.Dial(url, http.Header{"Origin": {"https://evil.example"}})
	if err == nil || resp == nil || resp.StatusCode != http.StatusForbidden {
		t.Fatalf("conexão com Origin de navegador deveria ser recusada (err=%v)", err)
	}
}

func TestShellAllowlistBlocks(t *testing.T) {
	cfg := config.Default()
	cfg.Shell.Allowlist = []string{"echo"}
	ts, _ := setup(t, cfg)
	c := dial(t, ts, nil)
	c.WriteJSON(map[string]any{"type": "ACTION", "action_type": "EXEC_SHELL", "button_id": "x",
		"payload": map[string]any{"command": "echo a; touch /tmp/pwned"}})
	m := readUntil(t, c, func(m map[string]any) bool { return m["button_id"] == "x" })
	if m["status"] != "ERROR" {
		t.Fatalf("deveria bloquear: %v", m)
	}
}
