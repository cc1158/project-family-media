package health

import (
	"log/slog"
	"path/filepath"
	"testing"

	"family-media-server/internal/platform/config"
)

func TestValidateEnvironment(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.Media.RootDir = dir
	cfg.Index.DBPath = filepath.Join(dir, "data", "media.db")
	cfg.Thumbnail.CacheDir = filepath.Join(dir, "thumbs")

	if err := ValidateEnvironment(cfg, slog.Default()); err != nil {
		t.Fatal(err)
	}
}

func TestValidateEnvironmentRequiresMediaRoot(t *testing.T) {
	cfg := config.Default()
	cfg.Media.RootDir = filepath.Join(t.TempDir(), "missing")
	cfg.Index.DBPath = filepath.Join(t.TempDir(), "data", "media.db")
	cfg.Thumbnail.CacheDir = filepath.Join(t.TempDir(), "thumbs")

	if err := ValidateEnvironment(cfg, slog.Default()); err == nil {
		t.Fatal("expected error")
	}
}
