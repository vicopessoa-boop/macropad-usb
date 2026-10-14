//go:build robotgo

package simulator

// Backend robotgo (cgo): menor latência e sem dependências externas em runtime.
// Compile com:  go build -tags robotgo ./cmd
// Requer as bibliotecas de desenvolvimento listadas em https://github.com/go-vgo/robotgo#requirements

import (
	"fmt"

	"github.com/go-vgo/robotgo"
)

type robotgoBackend struct{ typeDelay int }

func newPlatformBackend(typeDelayMs int) (Backend, error) {
	return robotgoBackend{typeDelay: typeDelayMs}, nil
}

func (robotgoBackend) Name() string { return "robotgo" }

var robotNames = map[string]string{
	"escape": "esc", "volumeup": "audio_vol_up", "volumedown": "audio_vol_down",
	"mute": "audio_mute", "playpause": "audio_play",
}

func robotName(k string) string {
	if n, ok := robotNames[k]; ok {
		return n
	}
	return k
}

func (robotgoBackend) KeyCombo(keys []string) error {
	var mods []string
	var key string
	for _, k := range keys {
		if IsModifier(k) {
			mods = append(mods, robotName(k))
		} else if key == "" {
			key = robotName(k)
		} else {
			return fmt.Errorf("robotgo aceita uma tecla não-modificadora por combinação: %v", keys)
		}
	}
	if key == "" {
		return fmt.Errorf("combinação só com modificadores: %v", keys)
	}
	args := make([]interface{}, len(mods))
	for i, m := range mods {
		args[i] = m
	}
	return robotgo.KeyTap(key, args...)
}

func (b robotgoBackend) TypeText(text string) error {
	robotgo.Type(text, 0, b.typeDelay) // args: pid (0 = janela ativa), atraso entre teclas
	return nil
}

func (robotgoBackend) SetClipboard(text string) error { return robotgo.WriteAll(text) }

func (robotgoBackend) GetClipboard() (string, error) { return robotgo.ReadAll() }
