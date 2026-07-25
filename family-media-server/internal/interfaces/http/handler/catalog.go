package handler

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	domainmedia "family-media-server/internal/domain/media"
	"family-media-server/internal/interfaces/http/middleware"
	"family-media-server/internal/interfaces/http/response"
)

type CatalogUseCase interface {
	Media(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error)
	Videos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error)
	Photos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error)
	Browse(ctx context.Context, kind domainmedia.Kind, containerID string, limit int, cursor string, sort domainmedia.Sort) (domainmedia.Page, error)
}

type TimelineCatalogUseCase interface {
	TimelineIndex(ctx context.Context, query domainmedia.TimelineQuery) (domainmedia.TimelineIndex, error)
	TimelineBrowse(ctx context.Context, query domainmedia.TimelineBrowseQuery) (domainmedia.Page, error)
}

type CatalogHandler struct {
	catalog  CatalogUseCase
	timeline TimelineCatalogUseCase
	logger   *slog.Logger
}

func NewCatalogHandler(catalog CatalogUseCase, timeline TimelineCatalogUseCase, logger *slog.Logger) *CatalogHandler {
	return &CatalogHandler{
		catalog:  catalog,
		timeline: timeline,
		logger:   logger,
	}
}

func (h *CatalogHandler) Videos(w http.ResponseWriter, r *http.Request) {
	page, err := h.catalog.Videos(r.Context(), listQuery(r))
	if err != nil {
		h.handleListError(w, r, "list_videos_failed", err)
		return
	}
	response.JSON(w, http.StatusOK, page)
}

func (h *CatalogHandler) Media(w http.ResponseWriter, r *http.Request) {
	page, err := h.catalog.Media(r.Context(), listQuery(r))
	if err != nil {
		h.handleListError(w, r, "list_media_failed", err)
		return
	}
	response.JSON(w, http.StatusOK, page)
}

func (h *CatalogHandler) Photos(w http.ResponseWriter, r *http.Request) {
	page, err := h.catalog.Photos(r.Context(), listQuery(r))
	if err != nil {
		h.handleListError(w, r, "list_photos_failed", err)
		return
	}
	response.JSON(w, http.StatusOK, page)
}

func (h *CatalogHandler) Browse(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	scope := r.URL.Query().Get("scope")
	if scope != "" && scope != "direct" && scope != "recursive" {
		response.Error(w, http.StatusBadRequest, "invalid_scope")
		return
	}
	kind, ok := browseKind(r.URL.Query().Get("kind"))
	if !ok {
		response.Error(w, http.StatusBadRequest, "invalid_media_kind")
		return
	}

	var page domainmedia.Page
	var err error
	if scope == "recursive" || r.URL.Query().Get("bucket") != "" {
		if h.timeline == nil {
			response.Error(w, http.StatusNotImplemented, "timeline_not_supported")
			return
		}
		page, err = h.timeline.TimelineBrowse(r.Context(), timelineBrowseQuery(r, kind, limit))
	} else {
		page, err = h.catalog.Browse(
			r.Context(),
			kind,
			r.URL.Query().Get("containerID"),
			limit,
			r.URL.Query().Get("cursor"),
			domainmedia.Sort(r.URL.Query().Get("sort")),
		)
	}
	if err != nil {
		h.handleListError(w, r, "browse_media_failed", err)
		return
	}
	response.JSON(w, http.StatusOK, page)
}

func (h *CatalogHandler) TimelineIndex(w http.ResponseWriter, r *http.Request) {
	kind, ok := browseKind(r.URL.Query().Get("kind"))
	if !ok {
		response.Error(w, http.StatusBadRequest, "invalid_media_kind")
		return
	}
	if h.timeline == nil {
		response.Error(w, http.StatusNotImplemented, "timeline_not_supported")
		return
	}
	index, err := h.timeline.TimelineIndex(r.Context(), timelineQuery(r, kind))
	if err != nil {
		h.handleListError(w, r, "timeline_index_failed", err)
		return
	}
	response.JSON(w, http.StatusOK, index)
}

func timelineQuery(r *http.Request, kind domainmedia.Kind) domainmedia.TimelineQuery {
	query := r.URL.Query()
	return domainmedia.TimelineQuery{
		Kind:        kind,
		ContainerID: query.Get("containerID"),
		TimeZone:    query.Get("timeZone"),
		Sort:        domainmedia.TimelineSort(query.Get("sort")),
	}
}

func timelineBrowseQuery(r *http.Request, kind domainmedia.Kind, limit int) domainmedia.TimelineBrowseQuery {
	query := r.URL.Query()
	return domainmedia.TimelineBrowseQuery{
		TimelineQuery: timelineQuery(r, kind),
		Bucket:        query.Get("bucket"),
		Limit:         limit,
		Cursor:        query.Get("cursor"),
	}
}

func browseKind(value string) (domainmedia.Kind, bool) {
	switch value {
	case "":
		return "", true
	case string(domainmedia.KindVideo):
		return domainmedia.KindVideo, true
	case string(domainmedia.KindPhoto):
		return domainmedia.KindPhoto, true
	default:
		return "", false
	}
}

func (h *CatalogHandler) handleListError(w http.ResponseWriter, r *http.Request, fallbackCode string, err error) {
	status, code := listErrorResponse(err)
	if code != "" {
		h.logRequestFailure(r, code, status, slog.LevelWarn)
		response.Error(w, status, code)
		return
	}
	h.logRequestFailure(r, fallbackCode, http.StatusInternalServerError, slog.LevelError)
	response.Error(w, http.StatusInternalServerError, fallbackCode)
}

func (h *CatalogHandler) logRequestFailure(r *http.Request, code string, status int, level slog.Level) {
	h.logger.Log(
		r.Context(),
		level,
		"catalog request failed",
		"event", "catalog_request_failed",
		"module", "catalog",
		"result", "failure",
		"operationID", middleware.OperationID(r.Context()),
		"errorCode", code,
		"statusClass", strconv.Itoa(status/100)+"xx",
	)
}

func listErrorResponse(err error) (int, string) {
	switch {
	case errors.Is(err, domainmedia.ErrInvalidCursor):
		return http.StatusBadRequest, "invalid_cursor"
	case errors.Is(err, domainmedia.ErrInvalidContainer):
		return http.StatusBadRequest, "invalid_container"
	case errors.Is(err, domainmedia.ErrInvalidSort):
		return http.StatusBadRequest, "invalid_sort"
	case errors.Is(err, domainmedia.ErrInvalidGroup):
		return http.StatusBadRequest, "invalid_group"
	case errors.Is(err, domainmedia.ErrInvalidTimeZone):
		return http.StatusBadRequest, "invalid_time_zone"
	case errors.Is(err, domainmedia.ErrInvalidBucket):
		return http.StatusBadRequest, "invalid_timeline_bucket"
	}
	return 0, ""
}

func listQuery(r *http.Request) domainmedia.ListQuery {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	return domainmedia.ListQuery{
		Limit:  limit,
		Cursor: r.URL.Query().Get("cursor"),
		Sort:   domainmedia.Sort(r.URL.Query().Get("sort")),
		Group:  domainmedia.Group(r.URL.Query().Get("group")),
	}
}
