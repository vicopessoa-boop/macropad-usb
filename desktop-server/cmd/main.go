// macropad-usb: daemon desktop que recebe ações do celular via USB (adb reverse)
// e simula teclado, cola snippets ou executa comandos de shell.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/adb"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/config"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/runner"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/server"
	"github.com/zxmarketingdigital/macropad-usb/desktop-server/internal/simulator"
)

func main() {
	cfgPath := flag.String("config", "config.json", "caminho do config.json")
	dryRun := flag.Bool("dry-run", false, "não simula teclado: apenas registra as ações no log")
	logPath := flag.String("log", "", "grava o log neste arquivo (útil rodando em segundo plano, sem janela)")
	noADB := flag.Bool("no-adb", false, "não gerencia o adb reverse (ex.: usando USB tethering)")
	port := flag.Int("port", 0, "sobrescreve a porta do config.json")
	flag.Parse()
	log.SetFlags(log.Ltime | log.Lmicroseconds)
	if *logPath != "" {
		f, err := os.OpenFile(*logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
		if err != nil {
			log.Fatalf("log: %v", err)
		}
		defer f.Close()
		log.SetOutput(f)
		log.SetFlags(log.Ldate | log.Ltime)
	}

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.Fatal(err)
	}
	if *port > 0 {
		cfg.Port = *port
	}

	sim, err := simulator.New(simulator.Options{
		DryRun:           *dryRun,
		TypeDelayMs:      cfg.TypeDelayMs,
		RestoreClipboard: cfg.RestoreClipboard,
	})
	if err != nil {
		log.Fatalf("simulador de teclado: %v", err)
	}
	run := runner.New(cfg.Shell.DefaultCwd, cfg.Shell.DefaultTimeoutSec, cfg.Shell.MaxConcurrent)
	srv := server.New(cfg, sim, run)

	addr := net.JoinHostPort(cfg.ListenAddr, fmt.Sprint(cfg.Port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("não foi possível escutar em %s: %v", addr, err)
	}
	httpSrv := &http.Server{Handler: srv.Handler(), ReadHeaderTimeout: 5 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if cfg.ADB.Enabled && !*noADB {
		bin, err := adb.Find(cfg.ADB.Path)
		if err != nil {
			log.Printf("aviso: %v — seguindo sem túnel USB (use USB tethering ou instale o adb)", err)
		} else {
			go adb.New(bin, cfg.Port, time.Duration(cfg.ADB.WatchIntervalSec)*time.Second).Watch(ctx)
		}
	}

	log.Printf("macropad-usb %s  ws://%s/ws  backend=%s  shell=%v  token=%v",
		server.Version, addr, sim.Name(), cfg.Shell.Enabled, cfg.Token != "")
	if cfg.ListenAddr != "127.0.0.1" && cfg.ListenAddr != "localhost" && cfg.Token == "" {
		log.Printf("ATENÇÃO: escutando fora do loopback sem token — qualquer dispositivo da rede pode disparar ações")
	}

	go func() {
		if err := httpSrv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()

	<-ctx.Done()
	log.Printf("encerrando...")
	srv.Shutdown()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	httpSrv.Shutdown(shutdownCtx)
}
