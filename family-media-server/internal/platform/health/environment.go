package health

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"

	"family-media-server/internal/platform/config"
)

func ValidateEnvironment(cfg config.Config, logger *slog.Logger) error {
	if err := requireReadableDir("media.rootDir", cfg.Media.RootDir); err != nil {
		return err
	}
	if err := requireWritableDir("thumbnail.cacheDir", cfg.Thumbnail.CacheDir); err != nil {
		return err
	}
	if err := requireWritableDir("index.dbPath directory", filepath.Dir(cfg.Index.DBPath)); err != nil {
		return err
	}
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		logger.Warn("ffmpeg not found; video thumbnails will be marked failed", "event", "ffmpeg_unavailable", "module", "health", "result", "failure")
	}
	return nil
}

func requireReadableDir(name string, path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("%s is not readable: %w", name, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("%s must be a directory: %s", name, path)
	}
	entries, err := os.ReadDir(path)
	if err != nil {
		return fmt.Errorf("%s is not readable: %w", name, err)
	}
	_ = entries
	return nil
}

func requireWritableDir(name string, path string) error {
	if err := os.MkdirAll(path, 0o755); err != nil {
		return fmt.Errorf("%s cannot be created: %w", name, err)
	}
	file, err := os.CreateTemp(path, ".write-check-*")
	if err != nil {
		return fmt.Errorf("%s is not writable: %w", name, err)
	}
	checkPath := file.Name()
	if err := file.Close(); err != nil {
		return fmt.Errorf("%s write check failed: %w", name, err)
	}
	if err := os.Remove(checkPath); err != nil {
		return fmt.Errorf("%s cleanup failed: %w", name, err)
	}
	return nil
}
