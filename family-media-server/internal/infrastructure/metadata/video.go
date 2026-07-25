package metadata

import (
	"context"
	"encoding/json"
	"os/exec"
	"strings"
	"time"
)

const ffprobeMetadataTimeout = 5 * time.Second

func videoCapturedAt(ctx context.Context, path string) (*time.Time, error) {
	if _, err := exec.LookPath("ffprobe"); err != nil {
		return nil, nil
	}
	ctx, cancel := context.WithTimeout(ctx, ffprobeMetadataTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "ffprobe", "-v", "error", "-show_entries", "format_tags=creation_time:stream_tags=creation_time", "-of", "json", path)
	output, err := cmd.Output()
	if err != nil {
		return nil, nil
	}

	var response ffprobeResponse
	if err := json.Unmarshal(output, &response); err != nil {
		return nil, err
	}
	for _, value := range response.creationTimes() {
		if parsed, ok := parseVideoTime(value); ok {
			return &parsed, nil
		}
	}
	return nil, nil
}

type ffprobeResponse struct {
	Format struct {
		Tags map[string]string `json:"tags"`
	} `json:"format"`
	Streams []struct {
		Tags map[string]string `json:"tags"`
	} `json:"streams"`
}

func (r ffprobeResponse) creationTimes() []string {
	values := make([]string, 0, len(r.Streams)+1)
	if value := tagValue(r.Format.Tags, "creation_time"); value != "" {
		values = append(values, value)
	}
	for _, stream := range r.Streams {
		if value := tagValue(stream.Tags, "creation_time"); value != "" {
			values = append(values, value)
		}
	}
	return values
}

func tagValue(tags map[string]string, key string) string {
	for tag, value := range tags {
		if strings.EqualFold(tag, key) {
			return value
		}
	}
	return ""
}

func parseVideoTime(value string) (time.Time, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, false
	}
	for _, layout := range []string{
		time.RFC3339Nano,
		"2006-01-02T15:04:05.000000Z",
		"2006-01-02 15:04:05",
	} {
		if parsed, err := time.Parse(layout, value); err == nil {
			return parsed.UTC(), true
		}
	}
	return time.Time{}, false
}
