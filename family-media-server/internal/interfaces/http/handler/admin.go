package handler

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"family-media-server/internal/application/jobs"
	"family-media-server/internal/application/maintenance"
	"family-media-server/internal/application/thumbnail"
	domainmedia "family-media-server/internal/domain/media"
	"family-media-server/internal/interfaces/http/response"
)

type ScanManager interface {
	Trigger() jobs.ScanStatus
	Status() jobs.ScanStatus
	RunMaintenance(ctx context.Context, operation func(context.Context) error) error
}

type ThumbnailRegenerator interface {
	Regenerate(ctx context.Context, id string, opts ...thumbnail.Option) (domainmedia.Item, error)
}

type GeneratedDataCleaner interface {
	Clear(ctx context.Context) (maintenance.Result, error)
}

type AdminHandler struct {
	scans      ScanManager
	thumbnails ThumbnailRegenerator
	cleaner    GeneratedDataCleaner
}

func NewAdminHandler(scans ScanManager, thumbnails ThumbnailRegenerator, cleaner GeneratedDataCleaner) *AdminHandler {
	return &AdminHandler{
		scans:      scans,
		thumbnails: thumbnails,
		cleaner:    cleaner,
	}
}

func (h *AdminHandler) TriggerScan(w http.ResponseWriter, r *http.Request) {
	status := h.scans.Trigger()
	response.JSON(w, http.StatusAccepted, map[string]string{
		"jobId":  status.JobID,
		"status": string(status.Status),
	})
}

func (h *AdminHandler) ScanStatus(w http.ResponseWriter, r *http.Request) {
	response.JSON(w, http.StatusOK, h.scans.Status())
}

func (h *AdminHandler) ClearGeneratedData(w http.ResponseWriter, r *http.Request) {
	request := clearGeneratedDataRequest{}
	if r.Body != nil {
		decoder := json.NewDecoder(r.Body)
		if err := decoder.Decode(&request); err != nil && !errors.Is(err, io.EOF) {
			response.Error(w, http.StatusBadRequest, "invalid_request_body")
			return
		}
	}

	if h.cleaner == nil {
		response.Error(w, http.StatusInternalServerError, "clear_generated_data_failed")
		return
	}
	var result maintenance.Result
	err := h.scans.RunMaintenance(r.Context(), func(ctx context.Context) error {
		var clearErr error
		result, clearErr = h.cleaner.Clear(ctx)
		return clearErr
	})
	if err != nil {
		if errors.Is(err, jobs.ErrMaintenanceBusy) {
			response.Error(w, http.StatusConflict, "media_scan_in_progress")
			return
		}
		response.Error(w, http.StatusInternalServerError, "clear_generated_data_failed")
		return
	}

	payload := clearGeneratedDataResponse{
		Status:             "cleared",
		ClearedDirectories: result.ClearedDirectories,
	}
	if request.Rescan {
		status := h.scans.Trigger()
		payload.Scan = &scanTriggerPayload{JobID: status.JobID, Status: string(status.Status)}
	}
	response.JSON(w, http.StatusOK, payload)
}

func (h *AdminHandler) RegenerateThumbnail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		response.Error(w, http.StatusBadRequest, "invalid_media_id")
		return
	}

	request := regenerateThumbnailRequest{}
	if r.Body != nil {
		decoder := json.NewDecoder(r.Body)
		if err := decoder.Decode(&request); err != nil && !errors.Is(err, io.EOF) {
			response.Error(w, http.StatusBadRequest, "invalid_request_body")
			return
		}
	}

	var opts []thumbnail.Option
	if request.TimeOffsetSeconds > 0 {
		opts = append(opts, thumbnail.WithTimeOffsetSeconds(request.TimeOffsetSeconds))
	}

	item, err := h.thumbnails.Regenerate(r.Context(), id, opts...)
	if err != nil {
		if errors.Is(err, domainmedia.ErrNotFound) {
			response.Error(w, http.StatusNotFound, "media_not_found")
			return
		}
		response.Error(w, http.StatusInternalServerError, "regenerate_thumbnail_failed")
		return
	}

	response.JSON(w, http.StatusOK, map[string]string{
		"id":              item.ID,
		"thumbnailStatus": string(item.ThumbnailStatus),
	})
}

type regenerateThumbnailRequest struct {
	TimeOffsetSeconds int `json:"timeOffsetSeconds"`
}

type clearGeneratedDataRequest struct {
	Rescan bool `json:"rescan"`
}

type clearGeneratedDataResponse struct {
	Status             string              `json:"status"`
	ClearedDirectories int                 `json:"clearedDirectories"`
	Scan               *scanTriggerPayload `json:"scan,omitempty"`
}

type scanTriggerPayload struct {
	JobID  string `json:"jobId"`
	Status string `json:"status"`
}
