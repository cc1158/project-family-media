package ffmpeg

import (
	"context"
	"errors"
	"image/jpeg"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
)

func TestThumbnailArgumentsRelyOnFFmpegDefaultAutorotation(t *testing.T) {
	tests := []struct {
		name string
		got  []string
		want []string
	}{
		{
			name: "video preferred frame",
			got:  videoThumbnailArgs("input.mp4", "thumb.jpg", 3, 480),
			want: []string{
				"-hide_banner", "-loglevel", "error",
				"-y", "-ss", "3", "-i", "input.mp4", "-frames:v", "1",
				"-vf", "scale=480:480:force_original_aspect_ratio=decrease",
				"-q:v", "3", "thumb.jpg",
			},
		},
		{
			name: "video first frame",
			got:  videoFirstFrameArgs("input.mov", "thumb.jpg", 320),
			want: []string{
				"-hide_banner", "-loglevel", "error",
				"-y", "-i", "input.mov", "-frames:v", "1",
				"-vf", "scale=320:320:force_original_aspect_ratio=decrease",
				"-q:v", "3", "thumb.jpg",
			},
		},
		{
			name: "image fallback",
			got:  imageThumbnailArgs("input.heic", "thumb.jpg", 240),
			want: []string{
				"-hide_banner", "-loglevel", "error",
				"-y", "-i", "input.heic", "-frames:v", "1",
				"-vf", "scale=240:240:force_original_aspect_ratio=decrease",
				"-q:v", "3", "thumb.jpg",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if slices.Contains(test.got, "-autorotate") {
				t.Fatalf("arguments must rely on FFmpeg's default autorotation: %#v", test.got)
			}
			if !reflect.DeepEqual(test.got, test.want) {
				t.Fatalf("arguments = %#v, want %#v", test.got, test.want)
			}
		})
	}
}

func TestGenerateVideoThumbnailFallsBackWhenPreferredFrameProducesNoFile(t *testing.T) {
	var calls [][]string
	outputPath := filepath.Join(t.TempDir(), "thumb.jpg")
	runner := func(_ context.Context, args ...string) error {
		calls = append(calls, slices.Clone(args))
		if len(calls) == 2 {
			return os.WriteFile(outputPath, []byte("generated"), 0o644)
		}
		return nil
	}

	err := generateVideoThumbnailWithRunner(
		context.Background(),
		runner,
		"short.mov",
		outputPath,
		3,
		480,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 2 {
		t.Fatalf("runner calls = %d, want 2", len(calls))
	}
	if !reflect.DeepEqual(calls[0], videoThumbnailArgs("short.mov", outputPath, 3, 480)) {
		t.Fatalf("preferred arguments = %#v", calls[0])
	}
	if !reflect.DeepEqual(calls[1], videoFirstFrameArgs("short.mov", outputPath, 480)) {
		t.Fatalf("fallback arguments = %#v", calls[1])
	}
}

func TestGenerateVideoThumbnailFallsBackAfterFFmpegFailure(t *testing.T) {
	var calls int
	outputPath := filepath.Join(t.TempDir(), "thumb.jpg")
	runner := func(_ context.Context, _ ...string) error {
		calls++
		if calls == 1 {
			return errors.New("preferred frame unavailable")
		}
		return os.WriteFile(outputPath, []byte("generated"), 0o644)
	}

	if err := generateVideoThumbnailWithRunner(
		context.Background(), runner, "short.mov", outputPath, 3, 480,
	); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("runner calls = %d, want 2", calls)
	}
}

func TestGenerateVideoThumbnailHonorsDisplayRotation(t *testing.T) {
	requireFFmpeg(t)
	dir := t.TempDir()
	basePath := filepath.Join(dir, "base.mp4")
	rotatedPath := filepath.Join(dir, "rotated.mp4")
	thumbnailPath := filepath.Join(dir, "thumb.jpg")

	runTestCommand(t,
		"-hide_banner", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "testsrc=size=80x60:rate=1:duration=1",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", basePath,
	)
	runTestCommand(t,
		"-hide_banner", "-loglevel", "error", "-y",
		"-display_rotation", "90", "-i", basePath,
		"-c", "copy", rotatedPath,
	)

	if err := generateVideoThumbnail(context.Background(), rotatedPath, thumbnailPath, 3, 480); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(thumbnailPath)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	thumbnail, err := jpeg.Decode(file)
	if err != nil {
		t.Fatal(err)
	}
	if width, height := thumbnail.Bounds().Dx(), thumbnail.Bounds().Dy(); width != 360 || height != 480 {
		t.Fatalf("rotated thumbnail size = %dx%d, want 360x480", width, height)
	}
}

func TestGenerateVideoThumbnailWithoutFFmpegFailsGracefully(t *testing.T) {
	t.Setenv("PATH", t.TempDir())

	err := generateVideoThumbnail(context.Background(), "input.mp4", filepath.Join(t.TempDir(), "thumb.jpg"), 3, 480)
	if err == nil || !strings.Contains(err.Error(), "ffmpeg not found") {
		t.Fatalf("err = %v", err)
	}
}

func requireFFmpeg(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg is not installed")
	}
}

func runTestCommand(t *testing.T, args ...string) {
	t.Helper()
	output, err := exec.Command("ffmpeg", args...).CombinedOutput()
	if err != nil {
		t.Fatalf("ffmpeg %v failed: %v\n%s", args, err, output)
	}
}
