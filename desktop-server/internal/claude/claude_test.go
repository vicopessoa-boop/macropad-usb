package claude

import (
	"testing"
	"time"
)

func TestFlow(t *testing.T) {
	tr := NewTracker()
	cwd := `C:\Users\Acer\zx-control-semana1`
	ev := func(name, ntype, msg string) bool {
		return tr.Apply(HookInput{SessionID: "s1", Cwd: cwd, HookEventName: name, NotificationType: ntype, Message: msg})
	}
	if !ev("UserPromptSubmit", "", "") {
		t.Fatal("primeiro evento deveria mudar o visor")
	}
	s := tr.Snapshot()[0]
	if s.State != StateWorking || s.Project != "zx-control-semana1" {
		t.Fatalf("%+v", s)
	}
	if ev("PostToolUse", "", "") {
		t.Fatal("PostToolUse repetido não deveria mudar o visor")
	}
	ev("Notification", "permission_prompt", "Claude needs your permission to use Bash")
	if got := tr.Snapshot()[0].State; got != StateWaiting {
		t.Fatalf("got %s", got)
	}
	ev("Notification", "idle_prompt", "Claude is waiting for your input")
	if got := tr.Snapshot()[0].State; got != StateAttention {
		t.Fatalf("got %s", got)
	}
	ev("PostToolUse", "", "")
	ev("PermissionRequest", "", "")
	if got := tr.Snapshot()[0].State; got != StateWaiting {
		t.Fatalf("PermissionRequest: got %s", got)
	}
	tr.Apply(HookInput{SessionID: "s1", HookEventName: "StopFailure", Error: "rate_limit"})
	if s := tr.Snapshot()[0]; s.State != StateAttention || s.Message != "Erro: rate_limit" {
		t.Fatalf("StopFailure: %+v", s)
	}
	if ev("Notification", "auth_success", "") {
		t.Fatal("auth_success não deveria mudar o visor")
	}
	ev("Stop", "", "")
	if got := tr.Snapshot()[0].State; got != StateDone {
		t.Fatalf("got %s", got)
	}
	if tr.Apply(HookInput{SessionID: "s1", HookEventName: "SubagentStop"}) {
		t.Fatal("evento desconhecido deveria ser ignorado")
	}
	ev("SessionEnd", "", "")
	if len(tr.Snapshot()) != 0 {
		t.Fatal("SessionEnd deveria remover a sessão")
	}
}

func TestStaleSessionsDropped(t *testing.T) {
	tr := NewTracker()
	base := time.Now()
	tr.now = func() time.Time { return base }
	tr.Apply(HookInput{SessionID: "a", HookEventName: "Stop", Cwd: "/home/x/proj"})
	tr.now = func() time.Time { return base.Add(4 * time.Hour) }
	if len(tr.Snapshot()) != 0 {
		t.Fatal("sessão antiga deveria sumir")
	}
}
