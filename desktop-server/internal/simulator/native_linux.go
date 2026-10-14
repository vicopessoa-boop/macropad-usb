//go:build linux && !robotgo

package simulator

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// Linux: xdotool no X11; wtype + wl-clipboard no Wayland.
type linuxBackend struct {
	wayland   bool
	typeDelay int
}

func newPlatformBackend(typeDelayMs int) (Backend, error) {
	wayland := os.Getenv("WAYLAND_DISPLAY") != ""
	if wayland {
		if _, err := exec.LookPath("wtype"); err == nil {
			return &linuxBackend{wayland: true, typeDelay: typeDelayMs}, nil
		}
	}
	if _, err := exec.LookPath("xdotool"); err != nil {
		return nil, errors.New("instale xdotool (X11) ou wtype (Wayland), ou rode com -dry-run")
	}
	return &linuxBackend{typeDelay: typeDelayMs}, nil
}

func (b *linuxBackend) Name() string {
	if b.wayland {
		return "wtype"
	}
	return "xdotool"
}

var xdoNames = map[string]string{
	"ctrl": "ctrl", "shift": "shift", "alt": "alt", "cmd": "super",
	"enter": "Return", "tab": "Tab", "space": "space", "escape": "Escape",
	"backspace": "BackSpace", "delete": "Delete", "insert": "Insert",
	"up": "Up", "down": "Down", "left": "Left", "right": "Right",
	"home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next",
	"volumeup": "XF86AudioRaiseVolume", "volumedown": "XF86AudioLowerVolume",
	"mute": "XF86AudioMute", "playpause": "XF86AudioPlay",
	"/": "slash", "\\": "backslash", ".": "period", ",": "comma", ";": "semicolon",
	"'": "apostrophe", "[": "bracketleft", "]": "bracketright", "-": "minus",
	"=": "equal", "`": "grave", "+": "plus", " ": "space",
}

var wtypeMods = map[string]string{"ctrl": "ctrl", "shift": "shift", "alt": "alt", "cmd": "logo"}

func xdoName(k string) string {
	if n, ok := xdoNames[k]; ok {
		return n
	}
	if isFunctionKey(k) {
		return strings.ToUpper(k)
	}
	return k
}

func (b *linuxBackend) KeyCombo(keys []string) error {
	if !b.wayland {
		names := make([]string, len(keys))
		for i, k := range keys {
			names[i] = xdoName(k)
		}
		return run("xdotool", "key", "--clearmodifiers", strings.Join(names, "+"))
	}
	var args, release []string
	for _, k := range keys {
		if m, ok := wtypeMods[k]; ok {
			args = append(args, "-M", m)
			release = append([]string{"-m", m}, release...)
		} else {
			args = append(args, "-k", xdoName(k))
		}
	}
	return run("wtype", append(args, release...)...)
}

func (b *linuxBackend) TypeText(text string) error {
	if b.wayland {
		return run("wtype", "-d", strconv.Itoa(b.typeDelay), "--", text)
	}
	return run("xdotool", "type", "--clearmodifiers", "--delay", strconv.Itoa(b.typeDelay), "--", text)
}

func (b *linuxBackend) SetClipboard(text string) error {
	name, args := b.clipboardCmd(false)
	if name == "" {
		return errors.New("instale xclip, xsel ou wl-clipboard")
	}
	cmd := exec.Command(name, args...)
	cmd.Stdin = strings.NewReader(text)
	// Sem capturar stdout/stderr: xclip e wl-copy ficam em segundo plano servindo a
	// área de transferência e herdariam o pipe, travando a espera.
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %v", name, err)
	}
	return nil
}

func (b *linuxBackend) GetClipboard() (string, error) {
	name, args := b.clipboardCmd(true)
	if name == "" {
		return "", ErrUnsupported
	}
	out, err := exec.Command(name, args...).Output()
	return string(out), err
}

func (b *linuxBackend) clipboardCmd(read bool) (string, []string) {
	candidates := [][]string{
		{"xclip", "-selection", "clipboard", "-i"},
		{"xsel", "--clipboard", "--input"},
	}
	if read {
		candidates = [][]string{
			{"xclip", "-selection", "clipboard", "-o"},
			{"xsel", "--clipboard", "--output"},
		}
	}
	if b.wayland {
		w := []string{"wl-copy"}
		if read {
			w = []string{"wl-paste", "--no-newline"}
		}
		candidates = append([][]string{w}, candidates...)
	}
	for _, c := range candidates {
		if _, err := exec.LookPath(c[0]); err == nil {
			return c[0], c[1:]
		}
	}
	return "", nil
}

func run(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %v %s", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}
