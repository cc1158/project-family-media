package imaging

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	domainmedia "family-media-server/internal/domain/media"
)

func TestGeneratePhotoThumbnail(t *testing.T) {
	dir := t.TempDir()
	inputPath := filepath.Join(dir, "input.jpg")
	outputPath := filepath.Join(dir, "thumb.jpg")
	writeJPEG(t, inputPath, 800, 600)

	generator := NewGenerator(480)
	if err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, inputPath, outputPath); err != nil {
		t.Fatal(err)
	}

	file, err := os.Open(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	cfg, err := jpeg.DecodeConfig(file)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Width != 480 || cfg.Height != 360 {
		t.Fatalf("thumbnail size = %dx%d", cfg.Width, cfg.Height)
	}
}

func TestGenerateStopsBeforeReadingWhenContextIsCanceled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err := NewGenerator(480).Generate(
		ctx,
		domainmedia.Item{Kind: domainmedia.KindPhoto},
		filepath.Join(t.TempDir(), "missing.jpg"),
		filepath.Join(t.TempDir(), "thumb.jpg"),
	)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
}

func TestGenerateAppliesJPEGEXIFOrientation(t *testing.T) {
	tests := []struct {
		name              string
		orientation       uint16
		wantWidth         int
		wantHeight        int
		originalTopLeftAt corner
	}{
		{name: "normal", orientation: 1, wantWidth: 80, wantHeight: 60, originalTopLeftAt: topLeft},
		{name: "mirror horizontal", orientation: 2, wantWidth: 80, wantHeight: 60, originalTopLeftAt: topRight},
		{name: "rotate 180", orientation: 3, wantWidth: 80, wantHeight: 60, originalTopLeftAt: bottomRight},
		{name: "mirror vertical", orientation: 4, wantWidth: 80, wantHeight: 60, originalTopLeftAt: bottomLeft},
		{name: "transpose", orientation: 5, wantWidth: 60, wantHeight: 80, originalTopLeftAt: topLeft},
		{name: "rotate clockwise", orientation: 6, wantWidth: 60, wantHeight: 80, originalTopLeftAt: topRight},
		{name: "transverse", orientation: 7, wantWidth: 60, wantHeight: 80, originalTopLeftAt: bottomRight},
		{name: "rotate counterclockwise", orientation: 8, wantWidth: 60, wantHeight: 80, originalTopLeftAt: bottomLeft},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			inputPath := filepath.Join(dir, "input.jpg")
			outputPath := filepath.Join(dir, "thumb.jpg")
			writeOrientedJPEG(t, inputPath, test.orientation)

			generator := NewGenerator(200)
			if err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, inputPath, outputPath); err != nil {
				t.Fatal(err)
			}

			thumbnail := decodeJPEG(t, outputPath)
			if thumbnail.Bounds().Dx() != test.wantWidth || thumbnail.Bounds().Dy() != test.wantHeight {
				t.Fatalf("thumbnail size = %dx%d", thumbnail.Bounds().Dx(), thumbnail.Bounds().Dy())
			}
			if !isMostlyRed(sampleCorner(thumbnail, test.originalTopLeftAt)) {
				t.Fatalf("original top-left was not transformed to %v", test.originalTopLeftAt)
			}
		})
	}
}

func TestGenerateIgnoresMalformedEXIFAndKeepsJPEGUsable(t *testing.T) {
	dir := t.TempDir()
	inputPath := filepath.Join(dir, "input.jpg")
	outputPath := filepath.Join(dir, "thumb.jpg")
	writeJPEGWithAPP1(t, inputPath, []byte("Exif\x00\x00broken"))

	if err := NewGenerator(200).Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, inputPath, outputPath); err != nil {
		t.Fatal(err)
	}
	thumbnail := decodeJPEG(t, outputPath)
	if thumbnail.Bounds().Dx() != 80 || thumbnail.Bounds().Dy() != 60 {
		t.Fatalf("thumbnail size = %dx%d", thumbnail.Bounds().Dx(), thumbnail.Bounds().Dy())
	}
}

func TestGeneratePNGThumbnail(t *testing.T) {
	dir := t.TempDir()
	inputPath := filepath.Join(dir, "input.png")
	outputPath := filepath.Join(dir, "thumb.jpg")
	file, err := os.Create(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := png.Encode(file, quadrantImage(800, 600)); err != nil {
		_ = file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}

	if err := NewGenerator(480).Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, inputPath, outputPath); err != nil {
		t.Fatal(err)
	}
	thumbnail := decodeJPEG(t, outputPath)
	if thumbnail.Bounds().Dx() != 480 || thumbnail.Bounds().Dy() != 360 {
		t.Fatalf("thumbnail size = %dx%d", thumbnail.Bounds().Dx(), thumbnail.Bounds().Dy())
	}
}

func writeJPEG(t *testing.T, path string, width int, height int) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, color.RGBA{R: 120, G: 160, B: 200, A: 255})
		}
	}
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if err := jpeg.Encode(file, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatal(err)
	}
}

type corner int

const (
	topLeft corner = iota
	topRight
	bottomLeft
	bottomRight
)

func writeOrientedJPEG(t *testing.T, path string, orientation uint16) {
	t.Helper()
	payload := bytes.NewBufferString("Exif\x00\x00")
	payload.Write([]byte{'I', 'I', 0x2A, 0x00})
	_ = binary.Write(payload, binary.LittleEndian, uint32(8))
	_ = binary.Write(payload, binary.LittleEndian, uint16(1))
	_ = binary.Write(payload, binary.LittleEndian, uint16(0x0112))
	_ = binary.Write(payload, binary.LittleEndian, uint16(3))
	_ = binary.Write(payload, binary.LittleEndian, uint32(1))
	_ = binary.Write(payload, binary.LittleEndian, orientation)
	_ = binary.Write(payload, binary.LittleEndian, uint16(0))
	_ = binary.Write(payload, binary.LittleEndian, uint32(0))
	writeJPEGWithAPP1(t, path, payload.Bytes())
}

func writeJPEGWithAPP1(t *testing.T, path string, payload []byte) {
	t.Helper()
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, quadrantImage(80, 60), &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	data := encoded.Bytes()
	if len(payload)+2 > 0xffff {
		t.Fatal("APP1 payload is too large")
	}
	var output bytes.Buffer
	output.Write(data[:2])
	output.Write([]byte{0xFF, 0xE1})
	_ = binary.Write(&output, binary.BigEndian, uint16(len(payload)+2))
	output.Write(payload)
	output.Write(data[2:])
	if err := os.WriteFile(path, output.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

func quadrantImage(width int, height int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	colors := [4]color.RGBA{
		{R: 240, G: 20, B: 20, A: 255},
		{R: 20, G: 220, B: 20, A: 255},
		{R: 20, G: 20, B: 240, A: 255},
		{R: 230, G: 210, B: 20, A: 255},
	}
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			index := 0
			if x >= width/2 {
				index++
			}
			if y >= height/2 {
				index += 2
			}
			img.Set(x, y, colors[index])
		}
	}
	return img
}

func decodeJPEG(t *testing.T, path string) image.Image {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	img, err := jpeg.Decode(file)
	if err != nil {
		t.Fatal(err)
	}
	return img
}

func sampleCorner(img image.Image, value corner) color.Color {
	bounds := img.Bounds()
	x := bounds.Min.X + bounds.Dx()/4
	y := bounds.Min.Y + bounds.Dy()/4
	switch value {
	case topRight:
		x = bounds.Min.X + bounds.Dx()*3/4
	case bottomLeft:
		y = bounds.Min.Y + bounds.Dy()*3/4
	case bottomRight:
		x = bounds.Min.X + bounds.Dx()*3/4
		y = bounds.Min.Y + bounds.Dy()*3/4
	}
	return img.At(x, y)
}

func isMostlyRed(value color.Color) bool {
	red, green, blue, _ := value.RGBA()
	return red > green*2 && red > blue*2
}
