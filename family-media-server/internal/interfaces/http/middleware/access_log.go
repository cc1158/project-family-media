package middleware

import (
	"log/slog"
	"net/http"
	"strings"
	"time"
)

func AccessLog(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		if !strings.HasPrefix(r.URL.Path, "/media/") {
			logger.Info(
				"http request",
				"event", "http_request_completed",
				"module", "http",
				"result", statusResult(recorder.status),
				"operationID", OperationID(r.Context()),
				"method", r.Method,
				"statusClass", statusClass(recorder.status),
				"durationMS", time.Since(start).Milliseconds(),
			)
		}
	})
}

func statusClass(status int) string {
	return string(rune('0'+status/100)) + "xx"
}

func statusResult(status int) string {
	if status >= http.StatusBadRequest {
		return "failure"
	}
	return "success"
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}
