package imaging

import (
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"os"

	imageops "github.com/disintegration/imaging"

	domainmedia "family-media-server/internal/domain/media"
)

type Generator struct {
	maxSide int
}

func NewGenerator(maxSide int) *Generator {
	return &Generator{maxSide: maxSide}
}

func (g *Generator) MaxSide() int {
	return g.maxSide
}

func (g *Generator) Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	img, err := imageops.Open(inputPath, imageops.AutoOrientation(true))
	if err != nil {
		return fmt.Errorf("decode image: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}

	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()
	return jpeg.Encode(out, resize(img, g.maxSide), &jpeg.Options{Quality: 75})
}

func resize(src image.Image, maxSide int) image.Image {
	bounds := src.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()
	if width <= maxSide && height <= maxSide {
		return src
	}

	newWidth := maxSide
	newHeight := height * maxSide / width
	if height > width {
		newHeight = maxSide
		newWidth = width * maxSide / height
	}
	if newWidth < 1 {
		newWidth = 1
	}
	if newHeight < 1 {
		newHeight = 1
	}

	dst := image.NewRGBA(image.Rect(0, 0, newWidth, newHeight))
	for y := 0; y < newHeight; y++ {
		for x := 0; x < newWidth; x++ {
			srcX := bounds.Min.X + x*width/newWidth
			srcY := bounds.Min.Y + y*height/newHeight
			dst.Set(x, y, src.At(srcX, srcY))
		}
	}
	return dst
}
