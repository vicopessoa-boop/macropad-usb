// Package config carrega o config.json do daemon.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Config struct {
	// Endereço de escuta. Mantenha em 127.0.0.1: o adb reverse entrega o tráfego do
	// celular no loopback do desktop, então não há motivo para expor na rede.
	ListenAddr string `json:"listen_addr"`
	Port       int    `json:"port"`

	// Token opcional exigido na mensagem HELLO. Vazio = sem autenticação.
	Token string `json:"token"`

	ADB ADBConfig `json:"adb"`

	Shell ShellConfig `json:"shell"`

	// Atraso entre teclas ao digitar texto (ms).
	TypeDelayMs int `json:"type_delay_ms"`

	// Restaura o conteúdo anterior da área de transferência após PASTE_SNIPPET.
	RestoreClipboard bool `json:"restore_clipboard"`

	// Perfis/layers enviados ao app ao conectar (formato livre, repassado como está).
	Layers json.RawMessage `json:"layers"`
}

type ADBConfig struct {
	Enabled bool   `json:"enabled"`
	Path    string `json:"path"` // vazio = procurar "adb" no PATH / ANDROID_HOME
	// Intervalo para reaplicar o reverse quando um aparelho reconectar (s).
	WatchIntervalSec int `json:"watch_interval_sec"`
}

type ShellConfig struct {
	// EXEC_SHELL é desabilitado se false.
	Enabled bool `json:"enabled"`
	// Se não vazio, só comandos que começam com um destes prefixos são aceitos.
	Allowlist         []string `json:"allowlist"`
	DefaultCwd        string   `json:"default_cwd"`
	DefaultTimeoutSec int      `json:"default_timeout_sec"`
	MaxConcurrent     int      `json:"max_concurrent"`
}

func Default() Config {
	return Config{
		ListenAddr:       "127.0.0.1",
		Port:             8080,
		ADB:              ADBConfig{Enabled: true, WatchIntervalSec: 3},
		Shell:            ShellConfig{Enabled: true, DefaultTimeoutSec: 300, MaxConcurrent: 4},
		TypeDelayMs:      2,
		RestoreClipboard: true,
	}
}

// Load lê o arquivo sobre os valores padrão. Arquivo ausente não é erro.
func Load(path string) (Config, error) {
	cfg := Default()
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return cfg, nil
	}
	if err != nil {
		return cfg, err
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("config %s: %w", path, err)
	}
	if cfg.Port <= 0 || cfg.Port > 65535 {
		return cfg, fmt.Errorf("config %s: porta inválida %d", path, cfg.Port)
	}
	if cfg.Shell.MaxConcurrent <= 0 {
		cfg.Shell.MaxConcurrent = 1
	}
	if cfg.ADB.WatchIntervalSec <= 0 {
		cfg.ADB.WatchIntervalSec = 3
	}
	if env := os.Getenv("MACROPAD_TOKEN"); env != "" {
		cfg.Token = env
	}
	return cfg, nil
}

// shellMeta são caracteres que permitiriam encadear outro comando após um prefixo liberado.
const shellMeta = ";&|`$()<>\n\r"

// ShellAllowed aplica a allowlist (se houver). Um item libera o comando idêntico,
// ou o mesmo comando com argumentos extras desde que não contenham metacaracteres
// de shell (evita "git pull; rm -rf ~" passar pelo prefixo "git pull").
func (c ShellConfig) ShellAllowed(cmd string) bool {
	if len(c.Allowlist) == 0 {
		return true
	}
	cmd = strings.TrimSpace(cmd)
	for _, p := range c.Allowlist {
		p = strings.TrimSpace(p)
		if cmd == p {
			return true
		}
		if rest, ok := strings.CutPrefix(cmd, p+" "); ok && !strings.ContainsAny(rest, shellMeta) {
			return true
		}
	}
	return false
}
