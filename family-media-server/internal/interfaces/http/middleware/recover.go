package middleware

import (
	"log/slog"
	"net/http"

	"family-media-server/internal/interfaces/http/response"
)

func Recover(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recover() != nil {
				logger.Error(
					"panic recovered",
					"event", "http_panic_recovered",
					"module", "http",
					"result", "failure",
					"operationID", OperationID(r.Context()),
				)
				response.Error(w, http.StatusInternalServerError, "internal_server_error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
