package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	applicationhealth "family-media-server/internal/application/health"
	"family-media-server/internal/application/jobs"
	"family-media-server/internal/application/maintenance"
	domainmedia "family-media-server/internal/domain/media"
	"family-media-server/internal/interfaces/http/handler"
)

func TestRouterHealthCatalogAndAdminRoutes(t *testing.T) {
	catalogService := fakeCatalog{
		page: domainmedia.Page{
			Items: []domainmedia.Item{{
				ID:              "1",
				Name:            "photo.jpg",
				Kind:            domainmedia.KindPhoto,
				ThumbnailStatus: domainmedia.ThumbnailPending,
			}},
			HasMore: true,
		},
	}
	catalog := handler.NewCatalogHandler(catalogService, nil, slog.Default())
	admin := handler.NewAdminHandler(
		&fakeScanManager{status: jobs.ScanStatus{JobID: "scan-1", Status: "running"}},
		nil,
		fakeGeneratedDataCleaner{},
	)
	router := NewRouter(handler.NewHealthHandler(fakeHealthChecker{}), catalog, admin, StaticMediaConfig{
		RootDir:  t.TempDir(),
		ThumbDir: t.TempDir(),
	})

	assertRoute(t, router, http.MethodGet, "/healthz", http.StatusOK, `"checks"`)
	assertRoute(t, router, http.MethodGet, "/api/v1/media?limit=1", http.StatusOK, `"items"`)
	assertRoute(t, router, http.MethodGet, "/api/v1/photos", http.StatusOK, `"hasMore":true`)
	assertRoute(t, router, http.MethodGet, "/api/v1/videos", http.StatusOK, `"items"`)
	assertRoute(t, router, http.MethodGet, "/api/v1/browse", http.StatusOK, `"items"`)
	assertRoute(t, router, http.MethodPost, "/api/v1/admin/scan", http.StatusAccepted, `"jobId":"scan-1"`)
	assertRoute(t, router, http.MethodGet, "/api/v1/admin/scan/status", http.StatusOK, `"status":"running"`)
	assertRoute(t, router, http.MethodPost, "/api/v1/admin/data/clear", http.StatusOK, `"status":"cleared"`)
}

func assertRoute(t *testing.T, router http.Handler, method string, path string, wantStatus int, wantBody string) {
	t.Helper()
	request := httptest.NewRequest(method, path, nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != wantStatus {
		t.Fatalf("%s %s status = %d", method, path, response.Code)
	}
	if !strings.Contains(response.Body.String(), wantBody) {
		t.Fatalf("%s %s body = %q, want %q", method, path, response.Body.String(), wantBody)
	}
}

type fakeCatalog struct {
	page domainmedia.Page
	err  error
}

func (c fakeCatalog) Media(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	return c.page, c.err
}

func (c fakeCatalog) Videos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	return c.page, c.err
}

func (c fakeCatalog) Photos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	return c.page, c.err
}

func (c fakeCatalog) Browse(ctx context.Context, kind domainmedia.Kind, containerID string, limit int, cursor string, sort domainmedia.Sort) (domainmedia.Page, error) {
	return c.page, c.err
}

type fakeScanManager struct {
	status jobs.ScanStatus
}

func (m *fakeScanManager) Trigger() jobs.ScanStatus {
	return m.status
}

func (m *fakeScanManager) Status() jobs.ScanStatus {
	return m.status
}

func (m *fakeScanManager) RunMaintenance(ctx context.Context, operation func(context.Context) error) error {
	return operation(ctx)
}

type fakeGeneratedDataCleaner struct{}

func (fakeGeneratedDataCleaner) Clear(context.Context) (maintenance.Result, error) {
	return maintenance.Result{ClearedDirectories: 2}, nil
}

type fakeHealthChecker struct{}

func (c fakeHealthChecker) Check(ctx context.Context) applicationhealth.Status {
	return applicationhealth.Status{
		Status: "ok",
		Checks: map[string]applicationhealth.Check{
			"mediaRoot": {Status: "ok", Message: "readable"},
		},
	}
}
