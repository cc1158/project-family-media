package handler

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"family-media-server/internal/application/jobs"
	"family-media-server/internal/application/maintenance"
	"family-media-server/internal/application/thumbnail"
	domainmedia "family-media-server/internal/domain/media"
)

func TestAdminHandlerTriggerScan(t *testing.T) {
	scans := &fakeScanManager{status: jobs.ScanStatus{JobID: "scan-1", Status: "running"}}
	handler := NewAdminHandler(scans, nil, nil)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/scan", nil)

	handler.TriggerScan(response, request)

	if response.Code != http.StatusAccepted {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), `"jobId":"scan-1"`) {
		t.Fatalf("body = %q", response.Body.String())
	}
	if scans.triggered != 1 {
		t.Fatalf("triggered = %d", scans.triggered)
	}
}

func TestAdminHandlerScanStatus(t *testing.T) {
	handler := NewAdminHandler(&fakeScanManager{status: jobs.ScanStatus{JobID: "scan-1", Status: "completed"}}, nil, nil)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/v1/admin/scan/status", nil)

	handler.ScanStatus(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), `"status":"completed"`) {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestAdminHandlerRegenerateThumbnail(t *testing.T) {
	regenerator := &fakeThumbnailRegenerator{
		item: domainmedia.Item{ID: "media-1", ThumbnailStatus: domainmedia.ThumbnailReady},
	}
	handler := NewAdminHandler(&fakeScanManager{}, regenerator, nil)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/media/media-1/thumbnail/regenerate", strings.NewReader(`{"timeOffsetSeconds":12}`))
	request.SetPathValue("id", "media-1")

	handler.RegenerateThumbnail(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if regenerator.id != "media-1" || regenerator.optionCount != 1 {
		t.Fatalf("regenerator = %#v", regenerator)
	}
	if !strings.Contains(response.Body.String(), `"thumbnailStatus":"ready"`) {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestAdminHandlerRegenerateThumbnailNotFound(t *testing.T) {
	handler := NewAdminHandler(&fakeScanManager{}, &fakeThumbnailRegenerator{err: domainmedia.ErrNotFound}, nil)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/media/missing/thumbnail/regenerate", nil)
	request.SetPathValue("id", "missing")

	handler.RegenerateThumbnail(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), `"error":"media_not_found"`) {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestAdminHandlerRegenerateThumbnailInvalidBody(t *testing.T) {
	handler := NewAdminHandler(&fakeScanManager{}, &fakeThumbnailRegenerator{}, nil)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/media/media-1/thumbnail/regenerate", strings.NewReader(`{`))
	request.SetPathValue("id", "media-1")

	handler.RegenerateThumbnail(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", response.Code)
	}
}

func TestAdminHandlerClearsGeneratedDataAndStartsRequestedScan(t *testing.T) {
	scans := &fakeScanManager{status: jobs.ScanStatus{JobID: "scan-new", Status: "running"}}
	cleaner := &fakeGeneratedDataCleaner{result: maintenance.Result{ClearedDirectories: 2}}
	handler := NewAdminHandler(scans, nil, cleaner)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/data/clear", strings.NewReader(`{"rescan":true}`))
	handler.ClearGeneratedData(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if cleaner.cleared != 1 || scans.triggered != 1 {
		t.Fatalf("cleaner clears = %d, scans = %d", cleaner.cleared, scans.triggered)
	}
	if !strings.Contains(response.Body.String(), `"status":"cleared"`) ||
		!strings.Contains(response.Body.String(), `"jobId":"scan-new"`) {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestAdminHandlerRejectsClearWhileScanIsRunning(t *testing.T) {
	scans := &fakeScanManager{maintenanceErr: jobs.ErrMaintenanceBusy}
	handler := NewAdminHandler(scans, nil, &fakeGeneratedDataCleaner{})

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/admin/data/clear", nil)
	handler.ClearGeneratedData(response, request)

	if response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), `"error":"media_scan_in_progress"`) {
		t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
	}
}

type fakeScanManager struct {
	status         jobs.ScanStatus
	triggered      int
	maintenanceErr error
}

func (m *fakeScanManager) Trigger() jobs.ScanStatus {
	m.triggered++
	return m.status
}

func (m *fakeScanManager) Status() jobs.ScanStatus {
	return m.status
}

func (m *fakeScanManager) RunMaintenance(ctx context.Context, operation func(context.Context) error) error {
	if m.maintenanceErr != nil {
		return m.maintenanceErr
	}
	return operation(ctx)
}

type fakeGeneratedDataCleaner struct {
	result  maintenance.Result
	err     error
	cleared int
}

func (c *fakeGeneratedDataCleaner) Clear(context.Context) (maintenance.Result, error) {
	c.cleared++
	return c.result, c.err
}

type fakeThumbnailRegenerator struct {
	id          string
	optionCount int
	item        domainmedia.Item
	err         error
}

func (r *fakeThumbnailRegenerator) Regenerate(ctx context.Context, id string, opts ...thumbnail.Option) (domainmedia.Item, error) {
	r.id = id
	r.optionCount = len(opts)
	if r.err != nil {
		if errors.Is(r.err, domainmedia.ErrNotFound) {
			return domainmedia.Item{}, r.err
		}
		return domainmedia.Item{}, r.err
	}
	return r.item, nil
}
