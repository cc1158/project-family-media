package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	domainmedia "family-media-server/internal/domain/media"
)

func TestCatalogHandlerReturnsPagedMedia(t *testing.T) {
	catalog := &fakeCatalog{
		page: domainmedia.Page{
			Items:      []domainmedia.Item{{ID: "1", Kind: domainmedia.KindPhoto}},
			NextCursor: "next",
			HasMore:    true,
		},
	}
	handler := NewCatalogHandler(catalog, catalog, slog.Default())

	request := httptest.NewRequest(http.MethodGet, "/api/v1/media?limit=1&sort=name_asc&group=month", nil)
	response := httptest.NewRecorder()

	handler.Media(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	body := response.Body.String()
	for _, want := range []string{`"items"`, `"nextCursor":"next"`, `"hasMore":true`} {
		if !strings.Contains(body, want) {
			t.Fatalf("body %q does not contain %q", body, want)
		}
	}
	if catalog.query.Limit != 1 || catalog.query.Sort != domainmedia.SortNameAsc || catalog.query.Group != domainmedia.GroupMonth {
		t.Fatalf("query = %#v", catalog.query)
	}
}

func TestCatalogHandlerInvalidCursorReturnsBadRequest(t *testing.T) {
	catalog := &fakeCatalog{err: domainmedia.ErrInvalidCursor}
	handler := NewCatalogHandler(catalog, catalog, slog.Default())

	request := httptest.NewRequest(http.MethodGet, "/api/v1/media?cursor=bad", nil)
	response := httptest.NewRecorder()

	handler.Media(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), "invalid_cursor") {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestCatalogHandlerPassesBrowseSort(t *testing.T) {
	catalog := &fakeCatalog{page: domainmedia.Page{Items: []domainmedia.Item{}}}
	handler := NewCatalogHandler(catalog, catalog, slog.Default())
	request := httptest.NewRequest(http.MethodGet, "/api/v1/browse?kind=video&limit=20&sort=name_desc", nil)
	response := httptest.NewRecorder()

	handler.Browse(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if catalog.query.Kind != domainmedia.KindVideo || catalog.query.Limit != 20 || catalog.query.Sort != domainmedia.SortNameDesc {
		t.Fatalf("query = %#v", catalog.query)
	}
}

func TestCatalogHandlerInvalidSortReturnsBadRequest(t *testing.T) {
	catalog := &fakeCatalog{err: domainmedia.ErrInvalidSort}
	handler := NewCatalogHandler(catalog, catalog, slog.Default())

	request := httptest.NewRequest(http.MethodGet, "/api/v1/media?sort=size_desc", nil)
	response := httptest.NewRecorder()

	handler.Media(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), "invalid_sort") {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestCatalogHandlerInvalidGroupReturnsBadRequest(t *testing.T) {
	catalog := &fakeCatalog{err: domainmedia.ErrInvalidGroup}
	handler := NewCatalogHandler(catalog, catalog, slog.Default())

	request := httptest.NewRequest(http.MethodGet, "/api/v1/media?group=day", nil)
	response := httptest.NewRecorder()

	handler.Media(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), "invalid_group") {
		t.Fatalf("body = %q", response.Body.String())
	}
}

func TestCatalogHandlerLogsKnownTimelineErrorCode(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	catalog := &fakeCatalog{timelineErr: domainmedia.ErrInvalidTimeZone}
	handler := NewCatalogHandler(catalog, catalog, logger)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/timeline/index?timeZone=Asia%2FShanghai", nil)
	response := httptest.NewRecorder()

	handler.TimelineIndex(response, request)

	if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), "invalid_time_zone") {
		t.Fatalf("status = %d body = %q", response.Code, response.Body.String())
	}
	var entry map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(logs.Bytes()), &entry); err != nil {
		t.Fatal(err)
	}
	if entry["errorCode"] != "invalid_time_zone" {
		t.Fatalf("log entry = %#v", entry)
	}
	if _, exists := entry["error"]; exists {
		t.Fatalf("raw error leaked into log entry: %#v", entry)
	}
}

func TestCatalogHandlerWithoutTimelineCapabilityReturnsNotImplemented(t *testing.T) {
	catalog := &fakeCatalog{}
	handler := NewCatalogHandler(catalog, nil, slog.Default())
	request := httptest.NewRequest(http.MethodGet, "/api/v1/timeline/index?timeZone=UTC", nil)
	response := httptest.NewRecorder()

	handler.TimelineIndex(response, request)
	if response.Code != http.StatusNotImplemented || !strings.Contains(response.Body.String(), "timeline_not_supported") {
		t.Fatalf("status = %d body = %q", response.Code, response.Body.String())
	}
}

type fakeCatalog struct {
	page        domainmedia.Page
	err         error
	timelineErr error
	query       domainmedia.ListQuery
}

func (c *fakeCatalog) Media(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	c.query = query
	return c.page, c.err
}

func (c *fakeCatalog) Videos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	c.query = query
	return c.page, c.err
}

func (c *fakeCatalog) Photos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	c.query = query
	return c.page, c.err
}

func (c *fakeCatalog) Browse(ctx context.Context, kind domainmedia.Kind, containerID string, limit int, cursor string, sort domainmedia.Sort) (domainmedia.Page, error) {
	c.query = domainmedia.ListQuery{Kind: kind, Limit: limit, Cursor: cursor, Sort: sort}
	return c.page, c.err
}

func (c *fakeCatalog) TimelineIndex(context.Context, domainmedia.TimelineQuery) (domainmedia.TimelineIndex, error) {
	return domainmedia.TimelineIndex{}, c.timelineErr
}

func (c *fakeCatalog) TimelineBrowse(context.Context, domainmedia.TimelineBrowseQuery) (domainmedia.Page, error) {
	return c.page, c.timelineErr
}
