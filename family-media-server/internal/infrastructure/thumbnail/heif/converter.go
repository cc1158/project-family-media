package heif

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
)

type Converter struct {
	run func(context.Context, string, string) error
}

func NewConverter() *Converter {
	return &Converter{run: runHEIFConvert}
}

func (c *Converter) Convert(ctx context.Context, inputPath string, outputPath string) error {
	return c.run(ctx, inputPath, outputPath)
}

func runHEIFConvert(ctx context.Context, inputPath string, outputPath string) error {
	if _, err := exec.LookPath("heif-convert"); err != nil {
		return errors.New("heif-convert not found")
	}
	cmd := exec.CommandContext(ctx, "heif-convert", inputPath, outputPath)
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("heif-convert exited: %w", err)
	}
	return nil
}
