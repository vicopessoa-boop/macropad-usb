package simulator

import (
	"reflect"
	"testing"
)

func TestNormalize(t *testing.T) {
	got, err := Normalize([]string{"Control", "SHIFT", "P"})
	if err != nil || !reflect.DeepEqual(got, []string{"ctrl", "shift", "p"}) {
		t.Fatalf("got %v %v", got, err)
	}
	got, _ = Normalize([]string{"mod", "Esc", "F12", "pgup"})
	want := []string{PrimaryModifier(), "escape", "f12", "pageup"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for _, bad := range [][]string{{}, {"f25"}, {"hyper"}, {"fx"}} {
		if _, err := Normalize(bad); err == nil {
			t.Errorf("esperava erro para %v", bad)
		}
	}
}

func TestDedent(t *testing.T) {
	in := "    if (x) {\n      y();\n\n    }"
	want := "if (x) {\n  y();\n\n}"
	if got := Dedent(in); got != want {
		t.Fatalf("got %q", got)
	}
	if got := Dedent("a\n  b"); got != "a\n  b" {
		t.Fatalf("sem indentação comum deveria ficar igual: %q", got)
	}
}

func TestSplitCursor(t *testing.T) {
	text, back := splitCursor("console.log('DEBUG:', $0);")
	if text != "console.log('DEBUG:', );" || back != 2 {
		t.Fatalf("got %q %d", text, back)
	}
	text, back = splitCursor("try {\n  $0\n} ç")
	if text != "try {\n  \n} ç" || back != 4 {
		t.Fatalf("got %q %d", text, back)
	}
}

type fakeBackend struct {
	combos [][]string
	clip   string
	sets   []string
}

func (f *fakeBackend) Name() string              { return "fake" }
func (f *fakeBackend) KeyCombo(k []string) error { f.combos = append(f.combos, k); return nil }
func (f *fakeBackend) TypeText(string) error     { return nil }
func (f *fakeBackend) SetClipboard(t string) error {
	f.sets = append(f.sets, t)
	f.clip = t
	return nil
}
func (f *fakeBackend) GetClipboard() (string, error) { return f.clip, nil }

func TestPasteSnippetRestoresClipboardAndMovesCursor(t *testing.T) {
	fb := &fakeBackend{clip: "anterior"}
	s := NewWithBackend(fb, Options{RestoreClipboard: true})
	if err := s.PasteSnippet("  f($0);", true); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(fb.sets, []string{"f();", "anterior"}) {
		t.Fatalf("clipboard: %v", fb.sets)
	}
	want := [][]string{{PrimaryModifier(), "v"}, {"left"}, {"left"}}
	if !reflect.DeepEqual(fb.combos, want) {
		t.Fatalf("combos: %v", fb.combos)
	}
}
