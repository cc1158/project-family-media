package handler

import (
	"context"
	"net/http"

	applicationhealth "family-media-server/internal/application/health"
	"family-media-server/internal/interfaces/http/response"
)

type HealthChecker interface {
	Check(ctx context.Context) applicationhealth.Status
}

type HealthHandler struct {
	checker HealthChecker
}

func NewHealthHandler(checker HealthChecker) *HealthHandler {
	return &HealthHandler{checker: checker}
}

func (h *HealthHandler) Check(w http.ResponseWriter, r *http.Request) {
	if h.checker == nil {
		response.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}
	response.JSON(w, http.StatusOK, h.checker.Check(r.Context()))
}
