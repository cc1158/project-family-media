package ffmpeg

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	domainmedia "family-media-server/internal/domain/media"
)

type Generator struct {
	maxSide int
	run     ffmpegRunner
}

func NewGenerator(maxSide int) *Generator {
	return &Generator{
		maxSide: maxSide,
		run:     runFFmpeg,
	}
}

func (g *Generator) Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	if item.Kind == domainmedia.KindVideo {
		return generateVideoThumbnailWithRunner(ctx, g.run, inputPath, outputPath, 3, g.maxSide)
	}
	return generateImageThumbnailWithRunner(ctx, g.run, inputPath, outputPath, g.maxSide)
}

func (g *Generator) GenerateAt(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string, timeOffsetSeconds int) error {
	if item.Kind != domainmedia.KindVideo {
		return g.Generate(ctx, item, inputPath, outputPath)
	}
	if timeOffsetSeconds <= 0 {
		timeOffsetSeconds = 3
	}
	return generateVideoThumbnailWithRunner(ctx, g.run, inputPath, outputPath, timeOffsetSeconds, g.maxSide)
}

type ffmpegRunner func(context.Context, ...string) error

func generateVideoThumbnail(ctx context.Context, inputPath string, outputPath string, timeOffsetSeconds int, maxSide int) error {
	return generateVideoThumbnailWithRunner(ctx, runFFmpeg, inputPath, outputPath, timeOffsetSeconds, maxSide)
}

func generateVideoThumbnailWithRunner(
	ctx context.Context,
	run ffmpegRunner,
	inputPath string,
	outputPath string,
	timeOffsetSeconds int,
	maxSide int,
) error {
	if err := runThumbnailCommand(
		ctx,
		run,
		outputPath,
		videoThumbnailArgs(inputPath, outputPath, timeOffsetSeconds, maxSide),
	); err == nil {
		return nil
	} else if timeOffsetSeconds <= 0 {
		return err
	}

	// Short iPhone clips and files without a keyframe near the preferred offset
	// still deserve a cover. Retry from the first decodable frame.
	return runThumbnailCommand(
		ctx,
		run,
		outputPath,
		videoFirstFrameArgs(inputPath, outputPath, maxSide),
	)
}

func generateImageThumbnail(ctx context.Context, inputPath string, outputPath string, maxSide int) error {
	return generateImageThumbnailWithRunner(ctx, runFFmpeg, inputPath, outputPath, maxSide)
}

func generateImageThumbnailWithRunner(
	ctx context.Context,
	run ffmpegRunner,
	inputPath string,
	outputPath string,
	maxSide int,
) error {
	return runThumbnailCommand(ctx, run, outputPath, imageThumbnailArgs(inputPath, outputPath, maxSide))
}

func runThumbnailCommand(ctx context.Context, run ffmpegRunner, outputPath string, args []string) error {
	if err := removeExistingOutput(outputPath); err != nil {
		return err
	}
	if err := run(ctx, args...); err != nil {
		return err
	}
	return validateGeneratedFile(outputPath, "ffmpeg")
}

func validateGeneratedFile(path string, producer string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("%s did not create output: %w", producer, err)
	}
	if !info.Mode().IsRegular() || info.Size() == 0 {
		return fmt.Errorf("%s created an invalid output", producer)
	}
	return nil
}

func removeExistingOutput(outputPath string) error {
	if err := os.Remove(outputPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove previous thumbnail output: %w", err)
	}
	return nil
}

func videoThumbnailArgs(inputPath string, outputPath string, timeOffsetSeconds int, maxSide int) []string {
	args := quietFFmpegArgs("-y", "-ss", strconv.Itoa(timeOffsetSeconds), "-i", inputPath, "-frames:v", "1")
	return appendThumbnailOutputArgs(args, outputPath, maxSide)
}

func videoFirstFrameArgs(inputPath string, outputPath string, maxSide int) []string {
	args := quietFFmpegArgs("-y", "-i", inputPath, "-frames:v", "1")
	return appendThumbnailOutputArgs(args, outputPath, maxSide)
}

func imageThumbnailArgs(inputPath string, outputPath string, maxSide int) []string {
	args := quietFFmpegArgs("-y", "-i", inputPath, "-frames:v", "1")
	return appendThumbnailOutputArgs(args, outputPath, maxSide)
}

func quietFFmpegArgs(args ...string) []string {
	return append([]string{"-hide_banner", "-loglevel", "error"}, args...)
}

func appendThumbnailOutputArgs(args []string, outputPath string, maxSide int) []string {
	args = appendScaleFilter(args, maxSide)
	return append(args, "-q:v", "3", outputPath)
}

func appendScaleFilter(args []string, maxSide int) []string {
	if maxSide <= 0 {
		return args
	}
	filter := fmt.Sprintf("scale=%d:%d:force_original_aspect_ratio=decrease", maxSide, maxSide)
	return append(args, "-vf", filter)
}

func runFFmpeg(ctx context.Context, args ...string) error {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return errors.New("ffmpeg not found")
	}
	cmd := exec.CommandContext(ctx, "ffmpeg", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("ffmpeg thumbnail failed: %s", message)
	}
	return nil
}
