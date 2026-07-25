package health

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"family-media-server/internal/application/jobs"
	"family-media-server/internal/platform/config"
)

func TestServiceCheckReportsOKWhenEnvironmentIsHealthy(t *testing.T) {
	dir := t.TempDir()
	installFakeHealthCommands(t)
	cfg := config.Default()
	cfg.Media.RootDir = dir
	cfg.Thumbnail.CacheDir = filepath.Join(dir, "thumbs")
	cfg.Index.DBPath = filepath.Join(dir, "data", "media.db")
	finished := time.Date(2026, 7, 5, 12, 0, 0, 0, time.UTC)

	service := NewService(cfg, fakeScans{status: jobs.ScanStatus{
		JobID:          "scan-1",
		Status:         "completed",
		FinishedAt:     &finished,
		ThumbnailError: "ffmpeg_thumbnail_failed",
	}})

	status := service.Check(context.Background())

	if status.Status != StatusOK {
		t.Fatalf("status = %q, want %q", status.Status, StatusOK)
	}
	if status.APIVersion != APIVersion {
		t.Fatalf("apiVersion = %d", status.APIVersion)
	}
	if len(status.Capabilities) != len(capabilities) {
		t.Fatalf("capabilities = %#v", status.Capabilities)
	}
	if status.Build.Version == "" || status.Build.Commit == "" || status.Build.Source == "" {
		t.Fatalf("build = %#v", status.Build)
	}
	if status.Checks["mediaRoot"].Status != CheckOK {
		t.Fatalf("mediaRoot status = %q", status.Checks["mediaRoot"].Status)
	}
	if status.Checks["thumbnailCache"].Status != CheckOK {
		t.Fatalf("thumbnailCache status = %q", status.Checks["thumbnailCache"].Status)
	}
	if status.Checks["indexDatabase"].Status != CheckOK {
		t.Fatalf("indexDatabase status = %q", status.Checks["indexDatabase"].Status)
	}
	if status.Scan == nil || status.Scan.JobID != "scan-1" || status.Scan.Status != "completed" {
		t.Fatalf("scan summary = %#v", status.Scan)
	}
	if status.Scan.ThumbnailError != "ffmpeg_thumbnail_failed" {
		t.Fatalf("scan thumbnail error = %#v", status.Scan)
	}
}

func TestServiceCheckReportsDegradedForBadPaths(t *testing.T) {
	dir := t.TempDir()
	installFakeHealthCommands(t)
	notDir := filepath.Join(dir, "not-dir")
	if err := os.WriteFile(notDir, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.Media.RootDir = notDir
	cfg.Thumbnail.CacheDir = notDir
	cfg.Index.DBPath = filepath.Join(notDir, "media.db")

	status := NewService(cfg, nil).Check(context.Background())

	if status.Status != StatusDegraded {
		t.Fatalf("status = %q, want %q", status.Status, StatusDegraded)
	}
	if status.Checks["mediaRoot"].Status != CheckError {
		t.Fatalf("mediaRoot status = %q", status.Checks["mediaRoot"].Status)
	}
	if status.Checks["thumbnailCache"].Status != CheckError {
		t.Fatalf("thumbnailCache status = %q", status.Checks["thumbnailCache"].Status)
	}
	if status.Checks["indexDatabase"].Status != CheckError {
		t.Fatalf("indexDatabase status = %q", status.Checks["indexDatabase"].Status)
	}
}

func TestServiceCheckReportsDegradedWhenFfmpegIsUnavailable(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.Media.RootDir = dir
	cfg.Thumbnail.CacheDir = filepath.Join(dir, "thumbs")
	cfg.Index.DBPath = filepath.Join(dir, "data", "media.db")

	t.Setenv("PATH", "")

	status := NewService(cfg, nil).Check(context.Background())

	if status.Status != StatusDegraded {
		t.Fatalf("status = %q, want %q", status.Status, StatusDegraded)
	}
	if status.Checks["ffmpeg"].Status != CheckWarning {
		t.Fatalf("ffmpeg status = %q", status.Checks["ffmpeg"].Status)
	}
}

func TestServiceCheckReportsDegradedWhenHEIFConverterIsUnavailable(t *testing.T) {
	dir := t.TempDir()
	binDir := t.TempDir()
	writeFakeCommand(t, binDir, "ffmpeg")
	t.Setenv("PATH", binDir)
	cfg := config.Default()
	cfg.Media.RootDir = dir
	cfg.Thumbnail.CacheDir = filepath.Join(dir, "thumbs")
	cfg.Index.DBPath = filepath.Join(dir, "data", "media.db")

	status := NewService(cfg, nil).Check(context.Background())

	if status.Status != StatusDegraded {
		t.Fatalf("status = %q, want %q", status.Status, StatusDegraded)
	}
	if status.Checks["heif"].Status != CheckWarning {
		t.Fatalf("heif status = %q", status.Checks["heif"].Status)
	}
}

func installFakeHealthCommands(t *testing.T) {
	t.Helper()
	binDir := t.TempDir()
	writeFakeCommand(t, binDir, "ffmpeg")
	writeFakeCommand(t, binDir, "heif-convert")
	t.Setenv("PATH", binDir)
}

func writeFakeCommand(t *testing.T, dir string, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
}

type fakeScans struct {
	status jobs.ScanStatus
}

func (s fakeScans) Status() jobs.ScanStatus {
	return s.status
}
