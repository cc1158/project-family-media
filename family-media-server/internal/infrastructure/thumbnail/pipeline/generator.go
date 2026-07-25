package pipeline

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	domainmedia "family-media-server/internal/domain/media"
)

type ImageGenerator interface {
	Generate(context.Context, domainmedia.Item, string, string) error
}

type FallbackGenerator interface {
	Generate(context.Context, domainmedia.Item, string, string) error
	GenerateAt(context.Context, domainmedia.Item, string, string, int) error
}

type HEIFConverter interface {
	Convert(context.Context, string, string) error
}

type Generator struct {
	native   ImageGenerator
	fallback FallbackGenerator
	heif     HEIFConverter
}

func NewGenerator(native ImageGenerator, fallback FallbackGenerator, heif HEIFConverter) *Generator {
	return &Generator{native: native, fallback: fallback, heif: heif}
}

func (g *Generator) Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if item.Kind == domainmedia.KindVideo {
		return wrap("ffmpeg_thumbnail_failed", g.fallback.Generate(ctx, item, inputPath, outputPath))
	}
	if isHEIF(inputPath) {
		return g.generateHEIF(ctx, item, inputPath, outputPath)
	}
	if err := g.native.Generate(ctx, item, inputPath, outputPath); err == nil {
		return nil
	}
	return wrap("ffmpeg_thumbnail_failed", g.fallback.Generate(ctx, item, inputPath, outputPath))
}

func (g *Generator) GenerateAt(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string, seconds int) error {
	if item.Kind != domainmedia.KindVideo {
		return g.Generate(ctx, item, inputPath, outputPath)
	}
	return wrap("ffmpeg_thumbnail_failed", g.fallback.GenerateAt(ctx, item, inputPath, outputPath, seconds))
}

func (g *Generator) generateHEIF(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	temporary, err := os.CreateTemp(filepath.Dir(outputPath), ".family-media-heif-*.png")
	if err != nil {
		return wrap("heif_conversion_failed", err)
	}
	temporaryPath := temporary.Name()
	if closeErr := temporary.Close(); closeErr != nil {
		_ = os.Remove(temporaryPath)
		return wrap("heif_conversion_failed", closeErr)
	}
	if err := os.Remove(temporaryPath); err != nil {
		return wrap("heif_conversion_failed", err)
	}
	defer os.Remove(temporaryPath)

	stageErr := g.heif.Convert(ctx, inputPath, temporaryPath)
	if stageErr == nil {
		if err := validateGeneratedFile(temporaryPath); err == nil {
			if err := g.native.Generate(ctx, item, temporaryPath, outputPath); err == nil {
				return nil
			} else {
				stageErr = err
			}
		} else {
			stageErr = err
		}
	}
	if err := g.fallback.Generate(ctx, item, inputPath, outputPath); err == nil {
		return nil
	}
	if errors.Is(stageErr, context.Canceled) || errors.Is(ctx.Err(), context.Canceled) {
		return context.Canceled
	}
	return wrap("heif_conversion_failed", stageErr)
}

func validateGeneratedFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() == 0 {
		return errors.New("converter produced invalid output")
	}
	return nil
}

func isHEIF(path string) bool {
	extension := strings.ToLower(filepath.Ext(path))
	return extension == ".heic" || extension == ".heif"
}

type GenerationError struct {
	code  string
	cause error
}

func (e *GenerationError) Error() string { return fmt.Sprintf("%s: %v", e.code, e.cause) }
func (e *GenerationError) Unwrap() error { return e.cause }
func (e *GenerationError) Code() string  { return e.code }

func wrap(code string, err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	return &GenerationError{code: code, cause: err}
}
