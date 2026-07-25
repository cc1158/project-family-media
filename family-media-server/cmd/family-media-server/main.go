package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"family-media-server/internal/bootstrap"
	"family-media-server/internal/platform/buildinfo"
)

func main() {
	build := buildinfo.Current()
	configPath := flag.String("config", "configs/config.yaml", "path to config file")
	flag.Parse()

	appCtx, stopBackground := context.WithCancel(context.Background())
	defer stopBackground()

	app, err := bootstrap.New(appCtx, *configPath)
	if err != nil {
		slog.Error("bootstrap application", "event", "application_bootstrap_failed", "module", "bootstrap", "result", "failure")
		os.Exit(1)
	}

	app.StartBackgroundJobs(appCtx)

	errCh := make(chan error, 1)
	go func() {
		app.Logger.Info(
			"family media server started",
			"event", "application_started",
			"module", "application",
			"result", "success",
			"version", build.Version,
			"commit", build.Commit,
			"binarySource", build.Source,
		)
		if err := app.Server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	shutdownCh := make(chan os.Signal, 1)
	signal.Notify(shutdownCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-shutdownCh:
		app.Logger.Info("shutdown requested", "event", "application_shutdown_requested", "module", "application", "result", "success", "signal", sig.String())
	case <-errCh:
		app.Logger.Error("server failed", "event", "http_server_failed", "module", "http", "result", "failure")
		os.Exit(1)
	}

	stopBackground()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := app.Server.Shutdown(ctx); err != nil {
		app.Logger.Error("graceful shutdown failed", "event", "http_shutdown_failed", "module", "http", "result", "failure")
		os.Exit(1)
	}
	if err := app.Jobs.Wait(ctx); err != nil {
		app.Logger.Error("background jobs did not stop", "event", "background_shutdown_timeout", "module", "jobs", "result", "failure")
		os.Exit(1)
	}
	app.Logger.Info("server stopped", "event", "application_stopped", "module", "application", "result", "success")
}
