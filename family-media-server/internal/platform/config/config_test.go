package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	content := []byte(`
server:
  host: "127.0.0.1"
  port: 9090
  publicBaseURL: "http://family-media.local:9090/"

media:
  rootDir: "/library"

index:
  enabled: true
  dbPath: "/data/index.db"

scan:
  intervalSeconds: 120

thumbnail:
  enabled: true
  cacheDir: "/data/thumbs"
  maxSide: 720
  batchSize: 25

transcode:
  enabled: false
  workDir: "/data/transcode"
`)
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}

	if got := cfg.Server.Addr(); got != "127.0.0.1:9090" {
		t.Fatalf("Addr() = %q", got)
	}
	if got := cfg.Server.PublicBaseURL; got != "http://family-media.local:9090" {
		t.Fatalf("PublicBaseURL = %q", got)
	}
	if cfg.Media.RootDir != "/library" {
		t.Fatalf("media config = %#v", cfg.Media)
	}
	if !cfg.Index.Enabled || cfg.Index.DBPath != "/data/index.db" {
		t.Fatalf("index config = %#v", cfg.Index)
	}
	if cfg.Scan.IntervalSeconds != 120 {
		t.Fatalf("scan config = %#v", cfg.Scan)
	}
	if !cfg.Thumbnail.Enabled || cfg.Thumbnail.CacheDir != "/data/thumbs" || cfg.Thumbnail.MaxSide != 720 || cfg.Thumbnail.BatchSize != 25 {
		t.Fatalf("thumbnail config = %#v", cfg.Thumbnail)
	}
	if cfg.Transcode.Enabled || cfg.Transcode.WorkDir != "/data/transcode" {
		t.Fatalf("transcode config = %#v", cfg.Transcode)
	}
}
