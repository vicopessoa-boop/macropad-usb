//go:build darwin && !robotgo

package simulator

import (
	"fmt"
	"os/exec"
	"strings"
)

// macOS: System Events via osascript (exige permissão de Acessibilidade para o terminal)
// e pbcopy/pbpaste para a área de transferência.
type darwinBackend struct{}

func newPlatformBackend(int) (Backend, error) { return darwinBackend{}, nil }

func (darwinBackend) Name() string { return "osascript" }

var macModifiers = map[string]string{
	"ctrl": "control down", "shift": "shift down", "alt": "option down", "cmd": "command down",
}

var macKeyCodes = map[string]int{
	"enter": 36, "tab": 48, "space": 49, "backspace": 51, "escape": 53, "delete": 117,
	"left": 123, "right": 124, "down": 125, "up": 126,
	"home": 115, "end": 119, "pageup": 116, "pagedown": 121,
	"f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
	"f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
	"f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
}

func (darwinBackend) KeyCombo(keys []string) error {
	var mods []string
	var key string
	for _, k := range keys {
		if m, ok := macModifiers[k]; ok {
			mods = append(mods, m)
		} else {
			key = k
		}
	}
	if key == "" {
		return fmt.Errorf("combinação só com modificadores não é suportada no macOS: %v", keys)
	}
	using := ""
	if len(mods) > 0 {
		using = " using {" + strings.Join(mods, ", ") + "}"
	}
	var stmt string
	if code, ok := macKeyCodes[key]; ok {
		stmt = fmt.Sprintf("key code %d%s", code, using)
	} else if len([]rune(key)) == 1 {
		stmt = fmt.Sprintf("keystroke %s%s", appleString(key), using)
	} else {
		return fmt.Errorf("tecla %q não suportada no macOS", key)
	}
	return osascript(`tell application "System Events" to ` + stmt)
}

func (darwinBackend) TypeText(text string) error {
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	var b strings.Builder
	b.WriteString("tell application \"System Events\"\n")
	for i, l := range lines {
		if i > 0 {
			b.WriteString("key code 36\n")
		}
		if l != "" {
			b.WriteString("keystroke " + appleString(l) + "\n")
		}
	}
	b.WriteString("end tell")
	return osascript(b.String())
}

func (darwinBackend) SetClipboard(text string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	return cmd.Run()
}

func (darwinBackend) GetClipboard() (string, error) {
	out, err := exec.Command("pbpaste").Output()
	return string(out), err
}

func appleString(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return `"` + s + `"`
}

func osascript(script string) error {
	out, err := exec.Command("osascript", "-e", script).CombinedOutput()
	if err != nil {
		return fmt.Errorf("osascript: %v %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
