// Package server expõe o WebSocket que recebe as ações do celular.
package server

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/config"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/protocol"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/runner"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/simulator"
)

const (
	Version      = "0.1.0"
	writeTimeout = 5 * time.Second
	helloTimeout = 5 * time.Second
	pingInterval = 20 * time.Second
	maxMsgBytes  = 64 << 10
)

type Server struct {
	cfg    config.Config
	sim    *simulator.Simulator
	runner *runner.Runner

	// Ações de teclado passam por uma fila única: a ordem dos toques é preservada
	// mesmo com mais de um celular conectado, e colagens não se atropelam.
	input chan inputJob

	mu      sync.Mutex
	clients map[*client]struct{}

	upgrader websocket.Upgrader
}

type inputJob struct {
	action *protocol.Action
	from   *client
}

type client struct {
	conn *websocket.Conn
	send chan []byte
	once sync.Once
}

func (c *client) close() { c.once.Do(func() { close(c.send) }) }

func New(cfg config.Config, sim *simulator.Simulator, run *runner.Runner) *Server {
	s := &Server{
		cfg:     cfg,
		sim:     sim,
		runner:  run,
		input:   make(chan inputJob, 64),
		clients: map[*client]struct{}{},
	}
	s.upgrader = websocket.Upgrader{
		ReadBufferSize:  4096,
		WriteBufferSize: 4096,
		// O app móvel não envia Origin. Navegadores sempre enviam: recusar evita que
		// uma página web qualquer aberta no desktop fale com ws://localhost e dispare comandos.
		CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == "" },
	}
	go s.inputWorker()
	return s
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", s.handleWS)
	mux.HandleFunc("/", s.handleWS)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		n := len(s.clients)
		s.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"ok": true, "version": Version, "backend": s.sim.Name(), "clients": n,
		})
	})
	return mux
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	if !websocket.IsWebSocketUpgrade(r) {
		http.Error(w, "macropad-usb: conecte via WebSocket em /ws", http.StatusUpgradeRequired)
		return
	}
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("ws: upgrade recusado (%s): %v", r.RemoteAddr, err)
		return
	}
	conn.SetReadLimit(maxMsgBytes)
	c := &client{conn: conn, send: make(chan []byte, 32)}
	go s.writeLoop(c)

	if err := s.handshake(c); err != nil {
		log.Printf("ws: handshake falhou (%s): %v", r.RemoteAddr, err)
		s.sendJSON(c, protocol.ErrorMsg{Type: protocol.TypeError, Message: err.Error()})
		time.Sleep(100 * time.Millisecond) // deixa o erro sair antes de fechar
		c.close()
		return
	}

	s.mu.Lock()
	s.clients[c] = struct{}{}
	s.mu.Unlock()
	log.Printf("ws: cliente conectado (%s)", r.RemoteAddr)

	defer func() {
		s.mu.Lock()
		delete(s.clients, c)
		s.mu.Unlock()
		c.close()
		log.Printf("ws: cliente desconectado (%s)", r.RemoteAddr)
	}()
	s.readLoop(c)
}

// handshake: com token configurado, a primeira mensagem precisa ser HELLO com o token.
// Sem token, o HELLO é opcional e qualquer primeira mensagem é processada normalmente.
func (s *Server) handshake(c *client) error {
	if s.cfg.Token == "" {
		s.greet(c)
		return nil
	}
	c.conn.SetReadDeadline(time.Now().Add(helloTimeout))
	_, data, err := c.conn.ReadMessage()
	if err != nil {
		return err
	}
	c.conn.SetReadDeadline(time.Time{})
	var h protocol.Hello
	if json.Unmarshal(data, &h) != nil || h.Type != protocol.TypeHello {
		return errors.New("esperado HELLO com token")
	}
	if subtle.ConstantTimeCompare([]byte(h.Token), []byte(s.cfg.Token)) != 1 {
		return errors.New("token inválido")
	}
	s.greet(c)
	return nil
}

func (s *Server) greet(c *client) {
	s.sendJSON(c, map[string]any{
		"type": protocol.TypeHello, "server": "macropad-usb", "version": Version, "backend": s.sim.Name(),
	})
	if len(s.cfg.Layers) > 0 && string(s.cfg.Layers) != "null" {
		s.sendJSON(c, protocol.Layout{Type: protocol.TypeLayout, Layers: s.cfg.Layers})
	}
}

func (s *Server) readLoop(c *client) {
	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				log.Printf("ws: leitura: %v", err)
			}
			return
		}
		s.handleMessage(c, data)
	}
}

func (s *Server) writeLoop(c *client) {
	ticker := time.NewTicker(pingInterval)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (s *Server) handleMessage(c *client, data []byte) {
	var env protocol.Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		s.sendJSON(c, protocol.ErrorMsg{Type: protocol.TypeError, Message: "JSON inválido"})
		return
	}
	switch env.Type {
	case protocol.TypePing:
		var p protocol.Ping
		json.Unmarshal(data, &p)
		s.sendJSON(c, protocol.Ping{Type: protocol.TypePong, TS: p.TS})
	case protocol.TypeHello:
		s.greet(c)
	case protocol.TypeAction:
		var a protocol.Action
		if err := json.Unmarshal(data, &a); err != nil {
			s.sendJSON(c, protocol.ErrorMsg{Type: protocol.TypeError, Message: "ACTION inválida"})
			return
		}
		s.dispatch(c, &a)
	default:
		s.sendJSON(c, protocol.ErrorMsg{Type: protocol.TypeError, Message: "tipo desconhecido: " + env.Type})
	}
}

func (s *Server) dispatch(c *client, a *protocol.Action) {
	switch a.ActionType {
	case protocol.ActionExecShell:
		s.execShell(a)
	case protocol.ActionKeyCombo, protocol.ActionPasteSnippet, protocol.ActionTypeText:
		select {
		case s.input <- inputJob{action: a, from: c}:
		default:
			s.sendJSON(c, protocol.NewStatus(a, protocol.StatusError, "fila de teclado cheia"))
		}
	default:
		s.sendJSON(c, protocol.NewStatus(a, protocol.StatusError, "action_type desconhecido: "+a.ActionType))
	}
}

func (s *Server) inputWorker() {
	for job := range s.input {
		start := time.Now()
		err := s.runInput(job.action)
		elapsed := time.Since(start)
		st := protocol.NewStatus(job.action, protocol.StatusSuccess, "")
		if err != nil {
			log.Printf("%s %s: %v", job.action.ActionType, job.action.ButtonID, err)
			st = protocol.NewStatus(job.action, protocol.StatusError, err.Error())
		}
		st.ElapsedMs = elapsed.Milliseconds()
		s.sendJSON(job.from, st)
	}
}

func (s *Server) runInput(a *protocol.Action) error {
	switch a.ActionType {
	case protocol.ActionKeyCombo:
		var p protocol.KeyComboPayload
		if err := json.Unmarshal(a.Payload, &p); err != nil {
			return fmt.Errorf("payload inválido: %w", err)
		}
		return s.sim.KeyCombo(p.Keys)
	case protocol.ActionPasteSnippet:
		var p protocol.PasteSnippetPayload
		if err := json.Unmarshal(a.Payload, &p); err != nil {
			return fmt.Errorf("payload inválido: %w", err)
		}
		return s.sim.PasteSnippet(p.Text, p.Indent)
	case protocol.ActionTypeText:
		var p protocol.TypeTextPayload
		if err := json.Unmarshal(a.Payload, &p); err != nil {
			return fmt.Errorf("payload inválido: %w", err)
		}
		return s.sim.TypeText(p.Text)
	}
	return nil
}

func (s *Server) execShell(a *protocol.Action) {
	var p protocol.ExecShellPayload
	if err := json.Unmarshal(a.Payload, &p); err != nil {
		s.broadcast(protocol.NewStatus(a, protocol.StatusError, "payload inválido"))
		return
	}
	if !s.cfg.Shell.Enabled {
		s.broadcast(protocol.NewStatus(a, protocol.StatusError, "EXEC_SHELL desabilitado no config.json"))
		return
	}
	if !s.cfg.Shell.ShellAllowed(p.Command) {
		log.Printf("EXEC_SHELL bloqueado pela allowlist: %q", p.Command)
		s.broadcast(protocol.NewStatus(a, protocol.StatusError, "comando fora da allowlist"))
		return
	}
	log.Printf("EXEC_SHELL [%s] %s", a.ButtonID, p.Command)
	started := func() { s.broadcast(protocol.NewStatus(a, protocol.StatusRunning, p.Command)) }
	err := s.runner.Run(a.ButtonID, p.Command, p.Cwd, p.TimeoutSec, started, func(r runner.Result) {
		st := protocol.NewStatus(a, protocol.StatusSuccess, r.Output)
		if r.Err != nil {
			msg := r.Err.Error()
			if r.Output != "" {
				msg += "\n" + r.Output
			}
			st = protocol.NewStatus(a, protocol.StatusError, msg)
		}
		st.ElapsedMs = r.Elapsed.Milliseconds()
		log.Printf("EXEC_SHELL [%s] %s em %s (exit %d)", a.ButtonID, st.Status, r.Elapsed.Round(time.Millisecond), r.ExitCode)
		s.broadcast(st)
	})
	if errors.Is(err, runner.ErrBusy) {
		// Não marca como erro: o comando anterior continua rodando e reportará o resultado.
		s.broadcast(protocol.NewStatus(a, protocol.StatusRunning, err.Error()))
	} else if err != nil {
		s.broadcast(protocol.NewStatus(a, protocol.StatusError, err.Error()))
	}
}

func (s *Server) sendJSON(c *client, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	defer func() { recover() }() // canal pode ter sido fechado por desconexão
	select {
	case c.send <- data:
	default:
		log.Printf("ws: cliente lento, mensagem descartada")
	}
}

// broadcast envia o status a todos os celulares conectados (comandos de shell podem
// terminar depois que o celular que disparou reconectou).
func (s *Server) broadcast(v any) {
	s.mu.Lock()
	targets := make([]*client, 0, len(s.clients))
	for c := range s.clients {
		targets = append(targets, c)
	}
	s.mu.Unlock()
	for _, c := range targets {
		s.sendJSON(c, v)
	}
}

// Shutdown cancela comandos em execução e fecha conexões.
func (s *Server) Shutdown() {
	s.runner.CancelAll()
	s.mu.Lock()
	defer s.mu.Unlock()
	for c := range s.clients {
		c.close()
	}
}
