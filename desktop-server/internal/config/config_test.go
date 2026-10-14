package config

import "testing"

func TestShellAllowed(t *testing.T) {
	c := ShellConfig{Allowlist: []string{"git pull", "npm test"}}
	cases := map[string]bool{
		"git pull":              true,
		"git pull origin main":  true,
		"git pull; rm -rf ~":    false,
		"git pull && curl x|sh": false,
		"git pull $(whoami)":    false,
		"git pullx":             false,
		"npm test -- --watch":   true,
		"rm -rf /":              false,
	}
	for cmd, want := range cases {
		if got := c.ShellAllowed(cmd); got != want {
			t.Errorf("%q: got %v want %v", cmd, got, want)
		}
	}
	if !(ShellConfig{}).ShellAllowed("qualquer coisa") {
		t.Error("allowlist vazia deveria liberar tudo")
	}
}
