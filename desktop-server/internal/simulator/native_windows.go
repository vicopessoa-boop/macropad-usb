//go:build windows && !robotgo

package simulator

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"sync"
)

// Windows: mantém um único processo PowerShell aberto (iniciar um por tecla custaria
// ~300 ms) e envia comandos por stdin. Teclas via user32!keybd_event, texto via
// SendKeys e área de transferência via Set-Clipboard.
type windowsBackend struct {
	mu    sync.Mutex
	stdin io.WriteCloser
	out   *bufio.Reader
}

const psBootstrap = `$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class MP{[DllImport("user32.dll")]static extern void keybd_event(byte vk,byte scan,uint flags,UIntPtr extra);public static void Combo(byte[] vks){foreach(var v in vks)keybd_event(v,0,0,UIntPtr.Zero);for(int i=vks.Length-1;i>=0;i--)keybd_event(vks[i],0,2,UIntPtr.Zero);}}'
function Dec($b){ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }
`

func newPlatformBackend(int) (Backend, error) {
	cmd := exec.Command("powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "-")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("powershell: %w", err)
	}
	b := &windowsBackend{stdin: stdin, out: bufio.NewReader(stdout)}
	for _, line := range strings.Split(psBootstrap, "\n") {
		if strings.TrimSpace(line) != "" {
			if _, err := b.exec(line); err != nil {
				return nil, err
			}
		}
	}
	return b, nil
}

func (b *windowsBackend) Name() string { return "powershell-user32" }

// exec envia uma linha e espera um marcador de fim, garantindo ordem e devolvendo a saída.
func (b *windowsBackend) exec(line string) (string, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	const marker = "__MP_DONE__"
	if _, err := fmt.Fprintf(b.stdin, "%s; Write-Output '%s'\n", line, marker); err != nil {
		return "", err
	}
	var out strings.Builder
	for {
		l, err := b.out.ReadString('\n')
		if err != nil {
			return out.String(), err
		}
		if strings.TrimSpace(l) == marker {
			return strings.TrimRight(out.String(), "\r\n"), nil
		}
		out.WriteString(l)
	}
}

var winVK = map[string]byte{
	"ctrl": 0x11, "shift": 0x10, "alt": 0x12, "cmd": 0x5B,
	"enter": 0x0D, "tab": 0x09, "space": 0x20, "escape": 0x1B, "backspace": 0x08,
	"delete": 0x2E, "insert": 0x2D, "home": 0x24, "end": 0x23, "pageup": 0x21, "pagedown": 0x22,
	"left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
	"volumeup": 0xAF, "volumedown": 0xAE, "mute": 0xAD, "playpause": 0xB3,
	";": 0xBA, "=": 0xBB, "+": 0xBB, ",": 0xBC, "-": 0xBD, ".": 0xBE, "/": 0xBF, "`": 0xC0,
	"[": 0xDB, "\\": 0xDC, "]": 0xDD, "'": 0xDE,
}

func vkFor(k string) (byte, error) {
	if v, ok := winVK[k]; ok {
		return v, nil
	}
	if isFunctionKey(k) {
		var n int
		fmt.Sscanf(k, "f%d", &n)
		return byte(0x70 + n - 1), nil
	}
	if len(k) == 1 {
		c := strings.ToUpper(k)[0]
		if (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
			return c, nil
		}
	}
	return 0, fmt.Errorf("tecla %q não suportada no Windows", k)
}

func (b *windowsBackend) KeyCombo(keys []string) error {
	codes := make([]string, len(keys))
	for i, k := range keys {
		v, err := vkFor(k)
		if err != nil {
			return err
		}
		codes[i] = fmt.Sprintf("0x%02X", v)
	}
	_, err := b.exec("[MP]::Combo([byte[]](" + strings.Join(codes, ",") + "))")
	return err
}

func (b *windowsBackend) TypeText(text string) error {
	_, err := b.exec("[System.Windows.Forms.SendKeys]::SendWait((Dec '" + b64(sendKeysEscape(text)) + "'))")
	return err
}

func (b *windowsBackend) SetClipboard(text string) error {
	_, err := b.exec("Set-Clipboard -Value (Dec '" + b64(text) + "')")
	return err
}

func (b *windowsBackend) GetClipboard() (string, error) {
	// Codifica em base64 para preservar quebras de linha na volta.
	out, err := b.exec("$c = Get-Clipboard -Raw; if ($c) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($c)) }")
	if err != nil {
		return "", err
	}
	dec, err := base64.StdEncoding.DecodeString(strings.TrimSpace(out))
	return string(dec), err
}

func b64(s string) string { return base64.StdEncoding.EncodeToString([]byte(s)) }

// sendKeysEscape protege os caracteres especiais do SendKeys.
func sendKeysEscape(s string) string {
	var b strings.Builder
	for _, r := range strings.ReplaceAll(s, "\r\n", "\n") {
		switch r {
		case '+', '^', '%', '~', '(', ')', '{', '}', '[', ']':
			b.WriteString("{" + string(r) + "}")
		case '\n':
			b.WriteString("{ENTER}")
		case '\t':
			b.WriteString("{TAB}")
		default:
			if r > 0xFFFF {
				continue // SendKeys não lida com pares substitutos (emoji etc.)
			}
			b.WriteRune(r)
		}
	}
	return b.String()
}
