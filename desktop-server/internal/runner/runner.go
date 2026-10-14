// Package runner executa comandos de shell de forma assíncrona, com timeout e
// limite de execuções simultâneas.
package runner

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

type Result struct {
	ExitCode int
	Output   string // últimas linhas de stdout+stderr
	Elapsed  time.Duration
	Err      error
}

type Runner struct {
	defaultCwd     string
	defaultTimeout time.Duration
	sem            chan struct{}

	mu      sync.Mutex
	running map[string]context.CancelFunc
}

func New(defaultCwd string, defaultTimeoutSec, maxConcurrent int) *Runner {
	if defaultTimeoutSec <= 0 {
		defaultTimeoutSec = 300
	}
	if maxConcurrent <= 0 {
		maxConcurrent = 1
	}
	return &Runner{
		defaultCwd:     expandHome(defaultCwd),
		defaultTimeout: time.Duration(defaultTimeoutSec) * time.Second,
		sem:            make(chan struct{}, maxConcurrent),
		running:        map[string]context.CancelFunc{},
	}
}

// ErrBusy indica que o mesmo botão ainda está rodando um comando.
var ErrBusy = errors.New("comando anterior deste botão ainda em execução")

// Run executa o comando em segundo plano. started é chamado de forma síncrona assim que
// o comando é aceito (antes de done, garantindo a ordem RUNNING → SUCCESS/ERROR) e done
// ao final. key (ex.: button_id) impede disparos duplicados do mesmo botão enquanto o
// anterior não terminou.
func (r *Runner) Run(key, command, cwd string, timeoutSec int, started func(), done func(Result)) error {
	if strings.TrimSpace(command) == "" {
		return errors.New("comando vazio")
	}
	timeout := r.defaultTimeout
	if timeoutSec > 0 {
		timeout = time.Duration(timeoutSec) * time.Second
	}
	if cwd == "" {
		cwd = r.defaultCwd
	}
	cwd = expandHome(cwd)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	if key != "" {
		r.mu.Lock()
		if _, busy := r.running[key]; busy {
			r.mu.Unlock()
			cancel()
			return ErrBusy
		}
		r.running[key] = cancel
		r.mu.Unlock()
	}
	if started != nil {
		started()
	}

	go func() {
		defer cancel()
		defer func() {
			if key != "" {
				r.mu.Lock()
				delete(r.running, key)
				r.mu.Unlock()
			}
		}()
		select {
		case r.sem <- struct{}{}:
			defer func() { <-r.sem }()
		case <-ctx.Done():
			done(Result{ExitCode: -1, Err: errors.New("timeout aguardando vaga para executar")})
			return
		}
		done(execute(ctx, command, cwd))
	}()
	return nil
}

// CancelAll encerra todos os comandos em execução (usado no shutdown).
func (r *Runner) CancelAll() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, c := range r.running {
		c()
	}
}

func execute(ctx context.Context, command, cwd string) Result {
	start := time.Now()
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.CommandContext(ctx, "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command)
	} else {
		shell := os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/sh"
		}
		cmd = exec.CommandContext(ctx, shell, "-lc", command)
	}
	cmd.Dir = cwd
	cmd.WaitDelay = 2 * time.Second
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()

	res := Result{Output: tail(buf.String(), 8, 600), Elapsed: time.Since(start)}
	switch {
	case err == nil:
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		res.ExitCode, res.Err = -1, fmt.Errorf("timeout após %s", res.Elapsed.Round(time.Second))
	default:
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			res.ExitCode = ee.ExitCode()
		} else {
			res.ExitCode = -1
		}
		res.Err = err
	}
	return res
}

// tail devolve as últimas n linhas, limitadas a max bytes.
func tail(s string, n, max int) string {
	s = strings.TrimRight(s, "\r\n")
	lines := strings.Split(s, "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	s = strings.Join(lines, "\n")
	if len(s) > max {
		s = "…" + s[len(s)-max:]
	}
	return s
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if h, err := os.UserHomeDir(); err == nil {
			return filepath.Join(h, strings.TrimPrefix(p, "~"))
		}
	}
	return p
}
