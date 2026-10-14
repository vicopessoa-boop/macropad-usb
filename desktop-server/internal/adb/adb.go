// Package adb mantém o túnel "adb reverse" ativo para cada aparelho conectado por USB,
// de modo que localhost:PORT no celular chegue a localhost:PORT no desktop.
package adb

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type Manager struct {
	bin      string
	port     int
	interval time.Duration
}

// Find localiza o executável adb: caminho explícito, PATH, ANDROID_HOME ou ANDROID_SDK_ROOT.
func Find(explicit string) (string, error) {
	if explicit != "" {
		if _, err := os.Stat(explicit); err != nil {
			return "", fmt.Errorf("adb não encontrado em %s", explicit)
		}
		return explicit, nil
	}
	if p, err := exec.LookPath("adb"); err == nil {
		return p, nil
	}
	name := "adb"
	if runtime.GOOS == "windows" {
		name = "adb.exe"
	}
	for _, env := range []string{"ANDROID_HOME", "ANDROID_SDK_ROOT"} {
		if root := os.Getenv(env); root != "" {
			p := filepath.Join(root, "platform-tools", name)
			if _, err := os.Stat(p); err == nil {
				return p, nil
			}
		}
	}
	return "", errors.New("adb não encontrado: instale o Android platform-tools ou defina adb.path no config.json")
}

func New(bin string, port int, interval time.Duration) *Manager {
	return &Manager{bin: bin, port: port, interval: interval}
}

// Devices lista os seriais em estado "device" (autorizados).
func (m *Manager) Devices(ctx context.Context) ([]string, error) {
	out, err := exec.CommandContext(ctx, m.bin, "devices").Output()
	if err != nil {
		return nil, err
	}
	return parseDevices(string(out)), nil
}

func parseDevices(out string) []string {
	var serials []string
	for _, line := range strings.Split(out, "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 && f[1] == "device" {
			serials = append(serials, f[0])
		}
	}
	return serials
}

// Reverse aplica "adb -s SERIAL reverse tcp:PORT tcp:PORT".
func (m *Manager) Reverse(ctx context.Context, serial string) error {
	spec := fmt.Sprintf("tcp:%d", m.port)
	out, err := exec.CommandContext(ctx, m.bin, "-s", serial, "reverse", spec, spec).CombinedOutput()
	if err != nil {
		return fmt.Errorf("adb reverse (%s): %v %s", serial, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func (m *Manager) hasReverse(ctx context.Context, serial string) bool {
	out, err := exec.CommandContext(ctx, m.bin, "-s", serial, "reverse", "--list").Output()
	return err == nil && strings.Contains(string(out), fmt.Sprintf("tcp:%d tcp:%d", m.port, m.port))
}

// Watch fica em loop: quando um aparelho aparece (ou perde o túnel após replug),
// reaplica o reverse. Retorna quando ctx é cancelado.
func (m *Manager) Watch(ctx context.Context) {
	// Garante que o servidor adb está de pé antes do primeiro "devices".
	_ = exec.CommandContext(ctx, m.bin, "start-server").Run()

	known := map[string]bool{}
	t := time.NewTicker(m.interval)
	defer t.Stop()
	for {
		tick, cancel := context.WithTimeout(ctx, 5*time.Second)
		serials, err := m.Devices(tick)
		if err != nil && ctx.Err() == nil {
			log.Printf("adb: falha ao listar aparelhos: %v", err)
		}
		current := map[string]bool{}
		for _, s := range serials {
			current[s] = true
			if known[s] && m.hasReverse(tick, s) {
				continue
			}
			if err := m.Reverse(tick, s); err != nil {
				log.Printf("adb: %v", err)
				continue
			}
			log.Printf("adb: túnel ativo  celular localhost:%d  →  desktop localhost:%d  [%s]", m.port, m.port, s)
		}
		for s := range known {
			if !current[s] {
				log.Printf("adb: aparelho desconectado [%s]", s)
			}
		}
		known = current
		cancel()

		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
