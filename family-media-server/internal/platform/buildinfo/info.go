package buildinfo

import (
	"os"
	"strings"
)

var (
	Version = "development"
	Commit  = "unknown"
	BuiltAt = "unknown"
)

type Info struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	BuiltAt string `json:"builtAt"`
	Source  string `json:"source"`
}

func Current() Info {
	return Info{
		Version: normalized(Version, "development"),
		Commit:  normalized(Commit, "unknown"),
		BuiltAt: normalized(BuiltAt, "unknown"),
		Source:  binarySource(),
	}
}

func binarySource() string {
	switch value := strings.TrimSpace(os.Getenv("FAMILY_MEDIA_BINARY_SOURCE")); value {
	case "external", "bundled":
		return value
	default:
		return "development"
	}
}

func normalized(value string, fallback string) string {
	if value = strings.TrimSpace(value); value != "" {
		return value
	}
	return fallback
}
