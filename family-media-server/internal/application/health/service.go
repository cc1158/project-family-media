package health

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"family-media-server/internal/application/jobs"
	"family-media-server/internal/platform/buildinfo"
	"family-media-server/internal/platform/config"
)

const (
	StatusOK       = "ok"
	StatusDegraded = "degraded"

	CheckOK      = "ok"
	CheckWarning = "warning"
	CheckError   = "error"

	APIVersion = 2

	CapabilityFolderBrowse       = "folder_browse"
	CapabilityGeneratedDataClear = "generated_data_clear"
	CapabilityThumbnailSelfHeal  = "thumbnail_self_heal"
	CapabilityBrowseSort         = "browse_sort"
	CapabilityTimelineIndex      = "timeline_index"
	CapabilityTimelineBrowse     = "timeline_browse"
)

var capabilities = []string{
	CapabilityFolderBrowse,
	CapabilityGeneratedDataClear,
	CapabilityThumbnailSelfHeal,
	CapabilityBrowseSort,
	CapabilityTimelineIndex,
	CapabilityTimelineBrowse,
}

type ScanStatusProvider interface {
	Status() jobs.ScanStatus
}

type Status struct {
	Status       string           `json:"status"`
	APIVersion   int              `json:"apiVersion"`
	Capabilities []string         `json:"capabilities"`
	Build        buildinfo.Info   `json:"build"`
	Checks       map[string]Check `json:"checks"`
	Scan         *ScanSummary     `json:"scan,omitempty"`
}

type Check struct {
	Status  string `json:"status"`
	Message string `json:"message"`
}

type ScanSummary struct {
	Status         string     `json:"status"`
	JobID          string     `json:"jobId,omitempty"`
	FinishedAt     *time.Time `json:"finishedAt,omitempty"`
	Error          string     `json:"error,omitempty"`
	ThumbnailError string     `json:"thumbnailError,omitempty"`
}

type Service struct {
	cfg   config.Config
	scans ScanStatusProvider
}

func NewService(cfg config.Config, scans ScanStatusProvider) *Service {
	return &Service{cfg: cfg, scans: scans}
}

func (s *Service) Check(ctx context.Context) Status {
	checks := map[string]Check{
		"mediaRoot":      readableDir(ctx, s.cfg.Media.RootDir),
		"thumbnailCache": writableDir(ctx, s.cfg.Thumbnail.CacheDir),
		"indexDatabase":  writableDir(ctx, filepath.Dir(s.cfg.Index.DBPath)),
		"ffmpeg":         commandAvailable("ffmpeg"),
		"heif":           commandAvailable("heif-convert"),
	}

	status := StatusOK
	for _, check := range checks {
		if check.Status != CheckOK {
			status = StatusDegraded
			break
		}
	}

	return Status{
		Status:       status,
		APIVersion:   APIVersion,
		Capabilities: append([]string(nil), capabilities...),
		Build:        buildinfo.Current(),
		Checks:       checks,
		Scan:         s.scanSummary(),
	}
}

func (s *Service) scanSummary() *ScanSummary {
	if s.scans == nil {
		return nil
	}

	status := s.scans.Status()
	if status.Status == "" {
		return nil
	}

	return &ScanSummary{
		Status:         string(status.Status),
		JobID:          status.JobID,
		FinishedAt:     status.FinishedAt,
		Error:          status.Error,
		ThumbnailError: status.ThumbnailError,
	}
}

func readableDir(ctx context.Context, path string) Check {
	if ctx.Err() != nil {
		return Check{Status: CheckError, Message: "cancelled"}
	}

	info, err := os.Stat(path)
	if err != nil {
		return Check{Status: CheckError, Message: "not readable"}
	}
	if !info.IsDir() {
		return Check{Status: CheckError, Message: "not a directory"}
	}
	if _, err := os.ReadDir(path); err != nil {
		return Check{Status: CheckError, Message: "not readable"}
	}
	return Check{Status: CheckOK, Message: "readable"}
}

func writableDir(ctx context.Context, path string) Check {
	if ctx.Err() != nil {
		return Check{Status: CheckError, Message: "cancelled"}
	}

	if err := os.MkdirAll(path, 0o755); err != nil {
		return Check{Status: CheckError, Message: "not writable"}
	}
	file, err := os.CreateTemp(path, ".health-check-*")
	if err != nil {
		return Check{Status: CheckError, Message: "not writable"}
	}
	checkPath := file.Name()
	if err := file.Close(); err != nil {
		return Check{Status: CheckError, Message: "write check failed"}
	}
	if err := os.Remove(checkPath); err != nil {
		return Check{Status: CheckWarning, Message: "cleanup failed"}
	}
	return Check{Status: CheckOK, Message: "writable"}
}

func commandAvailable(name string) Check {
	if _, err := exec.LookPath(name); err != nil {
		return Check{Status: CheckWarning, Message: "not available"}
	}
	return Check{Status: CheckOK, Message: "available"}
}
