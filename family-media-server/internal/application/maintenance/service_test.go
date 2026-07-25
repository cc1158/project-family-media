package maintenance

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestClearRemovesGeneratedFilesAndPreservesOriginalMedia(t *testing.T) {
	root := t.TempDir()
	mediaRoot := filepath.Join(root, "media")
	thumbnailDir := filepath.Join(root, "data", "thumbnails")
	transcodeDir := filepath.Join(root, "data", "transcode")
	indexPath := filepath.Join(root, "data", "media-index.db")
	writeTestFile(t, filepath.Join(mediaRoot, "family", "photo.heic"))
	writeTestFile(t, filepath.Join(thumbnailDir, "ab", "cover.jpg"))
	writeTestFile(t, filepath.Join(transcodeDir, "session", "segment.ts"))

	repository := &fakeGeneratedDataRepository{}
	service := NewService(repository, mediaRoot, indexPath, thumbnailDir, transcodeDir)
	result, err := service.Clear(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result.ClearedDirectories != 2 || repository.cleared != 1 {
		t.Fatalf("result = %#v, repository clears = %d", result, repository.cleared)
	}
	if _, err := os.Stat(filepath.Join(mediaRoot, "family", "photo.heic")); err != nil {
		t.Fatalf("original media was changed: %v", err)
	}
	assertDirectoryEmpty(t, thumbnailDir)
	assertDirectoryEmpty(t, transcodeDir)
}

func TestClearRejectsDirectoryOverlappingMediaRoot(t *testing.T) {
	root := t.TempDir()
	mediaRoot := filepath.Join(root, "media")
	writeTestFile(t, filepath.Join(mediaRoot, "photo.jpg"))
	service := NewService(
		&fakeGeneratedDataRepository{},
		mediaRoot,
		filepath.Join(root, "data", "index.db"),
		mediaRoot,
	)

	_, err := service.Clear(context.Background())
	if !errors.Is(err, ErrUnsafeGeneratedDataPath) {
		t.Fatalf("err = %v", err)
	}
	if _, err := os.Stat(filepath.Join(mediaRoot, "photo.jpg")); err != nil {
		t.Fatalf("original media was changed: %v", err)
	}
}

func TestClearRejectsDirectoryContainingIndexDatabase(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	service := NewService(
		&fakeGeneratedDataRepository{},
		filepath.Join(root, "media"),
		filepath.Join(dataDir, "index.db"),
		dataDir,
	)

	_, err := service.Clear(context.Background())
	if !errors.Is(err, ErrUnsafeGeneratedDataPath) {
		t.Fatalf("err = %v", err)
	}
}

func TestClearRejectsDirectoryReachedThroughSymbolicLinkParent(t *testing.T) {
	root := t.TempDir()
	mediaRoot := filepath.Join(root, "media")
	thumbnailDir := filepath.Join(mediaRoot, "generated-thumbnails")
	writeTestFile(t, filepath.Join(thumbnailDir, "cover.jpg"))
	linkedParent := filepath.Join(root, "linked")
	if err := os.Symlink(mediaRoot, linkedParent); err != nil {
		t.Skipf("symbolic links unavailable: %v", err)
	}
	service := NewService(
		&fakeGeneratedDataRepository{},
		mediaRoot,
		filepath.Join(root, "data", "index.db"),
		filepath.Join(linkedParent, "generated-thumbnails"),
	)

	_, err := service.Clear(context.Background())
	if !errors.Is(err, ErrUnsafeGeneratedDataPath) {
		t.Fatalf("err = %v", err)
	}
	if _, err := os.Stat(filepath.Join(thumbnailDir, "cover.jpg")); err != nil {
		t.Fatalf("linked content was changed: %v", err)
	}
}

type fakeGeneratedDataRepository struct {
	cleared int
}

func (r *fakeGeneratedDataRepository) ClearGeneratedData(context.Context) error {
	r.cleared++
	return nil
}

func writeTestFile(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("test"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertDirectoryEmpty(t *testing.T, path string) {
	t.Helper()
	entries, err := os.ReadDir(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("directory %s contains %d entries", path, len(entries))
	}
}
