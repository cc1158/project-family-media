package httpapi

import (
	"log/slog"
	"net/http"
	"time"

	"family-media-server/internal/interfaces/http/middleware"
	"family-media-server/internal/platform/config"
)

func NewServer(cfg config.Config, router http.Handler, logger *slog.Logger) *http.Server {
	return &http.Server{
		Addr:              cfg.Server.Addr(),
		Handler:           middleware.Operation(middleware.AccessLog(logger, middleware.Recover(logger, router))),
		ReadHeaderTimeout: 5 * time.Second,
	}
}
