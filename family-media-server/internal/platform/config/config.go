package config

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Server    ServerConfig
	Media     MediaConfig
	Index     IndexConfig
	Scan      ScanConfig
	Thumbnail ThumbnailConfig
	Transcode TranscodeConfig
}

type ServerConfig struct {
	Host          string
	Port          int
	PublicBaseURL string
}

type MediaConfig struct {
	RootDir string
}

type IndexConfig struct {
	Enabled bool
	DBPath  string
}

type ScanConfig struct {
	IntervalSeconds int
}

type ThumbnailConfig struct {
	Enabled   bool
	CacheDir  string
	MaxSide   int
	BatchSize int
}

type TranscodeConfig struct {
	Enabled bool
	WorkDir string
}

func Default() Config {
	return Config{
		Server: ServerConfig{
			Host:          "0.0.0.0",
			Port:          8080,
			PublicBaseURL: "http://localhost:8080",
		},
		Media: MediaConfig{
			RootDir: "/media/library",
		},
		Index: IndexConfig{
			Enabled: false,
			DBPath:  "./data/media-index.db",
		},
		Scan: ScanConfig{
			IntervalSeconds: 600,
		},
		Thumbnail: ThumbnailConfig{
			Enabled:   false,
			CacheDir:  "./data/thumbnails",
			MaxSide:   480,
			BatchSize: 100,
		},
		Transcode: TranscodeConfig{
			Enabled: false,
			WorkDir: "./data/transcode",
		},
	}
}

func Load(path string) (Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("open config %q: %w", path, err)
	}
	defer file.Close()

	cfg, err := Parse(file)
	if err != nil {
		return Config{}, fmt.Errorf("parse config %q: %w", path, err)
	}
	return cfg, nil
}

func Parse(reader io.Reader) (Config, error) {
	cfg := Default()

	values, err := parseSimpleYAML(reader)
	if err != nil {
		return cfg, err
	}

	if value := values["server.host"]; value != "" {
		cfg.Server.Host = value
	}
	if value := values["server.port"]; value != "" {
		port, err := strconv.Atoi(value)
		if err != nil || port <= 0 || port > 65535 {
			return cfg, fmt.Errorf("server.port must be a valid TCP port")
		}
		cfg.Server.Port = port
	}
	if value := values["server.publicBaseURL"]; value != "" {
		cfg.Server.PublicBaseURL = strings.TrimRight(value, "/")
	}
	if value := values["media.rootDir"]; value != "" {
		cfg.Media.RootDir = value
	}
	if value := values["index.enabled"]; value != "" {
		cfg.Index.Enabled, err = parseBool("index.enabled", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["index.dbPath"]; value != "" {
		cfg.Index.DBPath = value
	}
	if value := values["scan.intervalSeconds"]; value != "" {
		cfg.Scan.IntervalSeconds, err = parsePositiveInt("scan.intervalSeconds", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["thumbnail.enabled"]; value != "" {
		cfg.Thumbnail.Enabled, err = parseBool("thumbnail.enabled", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["thumbnail.cacheDir"]; value != "" {
		cfg.Thumbnail.CacheDir = value
	}
	if value := values["thumbnail.maxSide"]; value != "" {
		cfg.Thumbnail.MaxSide, err = parsePositiveInt("thumbnail.maxSide", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["thumbnail.batchSize"]; value != "" {
		cfg.Thumbnail.BatchSize, err = parsePositiveInt("thumbnail.batchSize", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["transcode.enabled"]; value != "" {
		cfg.Transcode.Enabled, err = parseBool("transcode.enabled", value)
		if err != nil {
			return cfg, err
		}
	}
	if value := values["transcode.workDir"]; value != "" {
		cfg.Transcode.WorkDir = value
	}

	if cfg.Media.RootDir == "" {
		return cfg, fmt.Errorf("media.rootDir is required")
	}

	return cfg, nil
}

func (c ServerConfig) Addr() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

func parseBool(key string, value string) (bool, error) {
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean", key)
	}
	return parsed, nil
}

func parsePositiveInt(key string, value string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", key)
	}
	return parsed, nil
}

func parseSimpleYAML(reader io.Reader) (map[string]string, error) {
	scanner := bufio.NewScanner(reader)
	values := make(map[string]string)
	var section string

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasSuffix(line, ":") {
			section = strings.TrimSuffix(line, ":")
			continue
		}

		key, value, found := strings.Cut(line, ":")
		if !found {
			return nil, fmt.Errorf("invalid line %q", line)
		}

		key = strings.TrimSpace(key)
		value = strings.Trim(strings.TrimSpace(value), `"'`)
		if section != "" {
			key = section + "." + key
		}
		values[key] = value
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return values, nil
}
