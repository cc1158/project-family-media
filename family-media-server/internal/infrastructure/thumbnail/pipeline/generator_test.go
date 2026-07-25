package pipeline

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	domainmedia "family-media-server/internal/domain/media"
)

func TestRoutesVideoDirectlyToFFmpeg(t *testing.T) {
	fallback := &fakeFallback{}
	generator := NewGenerator(&fakeNative{}, fallback, &fakeHEIF{})
	if err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindVideo}, "clip.mov", "thumb.jpg"); err != nil {
		t.Fatal(err)
	}
	if fallback.calls != 1 {
		t.Fatalf("fallback calls = %d", fallback.calls)
	}
}

func TestNativePhotoFailureFallsBackToFFmpeg(t *testing.T) {
	native := &fakeNative{err: errors.New("unsupported")}
	fallback := &fakeFallback{}
	generator := NewGenerator(native, fallback, &fakeHEIF{})
	if err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, "photo.raw", "thumb.jpg"); err != nil {
		t.Fatal(err)
	}
	if native.calls != 1 || fallback.calls != 1 {
		t.Fatalf("native/fallback calls = %d/%d", native.calls, fallback.calls)
	}
}

func TestHEIFConversionUsesTemporaryFileAndCleansIt(t *testing.T) {
	dir := t.TempDir()
	native := &fakeNative{writeOutput: true}
	converter := &fakeHEIF{writeOutput: true}
	generator := NewGenerator(native, &fakeFallback{}, converter)
	output := filepath.Join(dir, "thumb.jpg")
	if err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, filepath.Join(dir, "photo.HEIC"), output); err != nil {
		t.Fatal(err)
	}
	if converter.output == "" {
		t.Fatal("converter was not called")
	}
	if _, err := os.Stat(converter.output); !os.IsNotExist(err) {
		t.Fatalf("temporary file still exists: %v", err)
	}
}

func TestHEIFFailureFallsBackAndReturnsStableCode(t *testing.T) {
	generator := NewGenerator(
		&fakeNative{},
		&fakeFallback{err: errors.New("unsupported")},
		&fakeHEIF{err: errors.New("converter unavailable")},
	)
	err := generator.Generate(context.Background(), domainmedia.Item{Kind: domainmedia.KindPhoto}, "photo.heif", filepath.Join(t.TempDir(), "thumb.jpg"))
	var coded interface{ Code() string }
	if !errors.As(err, &coded) || coded.Code() != "heif_conversion_failed" {
		t.Fatalf("error = %v", err)
	}
}

func TestCancellationSkipsPipeline(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := NewGenerator(&fakeNative{}, &fakeFallback{}, &fakeHEIF{}).Generate(
		ctx,
		domainmedia.Item{Kind: domainmedia.KindPhoto},
		"photo.heic",
		"thumb.jpg",
	)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v", err)
	}
}

type fakeNative struct {
	calls       int
	err         error
	writeOutput bool
}

func (g *fakeNative) Generate(_ context.Context, _ domainmedia.Item, _ string, output string) error {
	g.calls++
	if g.err == nil && g.writeOutput {
		return os.WriteFile(output, []byte("thumbnail"), 0o644)
	}
	return g.err
}

type fakeFallback struct {
	calls int
	err   error
}

func (g *fakeFallback) Generate(context.Context, domainmedia.Item, string, string) error {
	g.calls++
	return g.err
}

func (g *fakeFallback) GenerateAt(context.Context, domainmedia.Item, string, string, int) error {
	g.calls++
	return g.err
}

type fakeHEIF struct {
	err         error
	writeOutput bool
	output      string
}

func (c *fakeHEIF) Convert(_ context.Context, _ string, output string) error {
	c.output = output
	if c.err == nil && c.writeOutput {
		return os.WriteFile(output, []byte("converted"), 0o644)
	}
	return c.err
}
