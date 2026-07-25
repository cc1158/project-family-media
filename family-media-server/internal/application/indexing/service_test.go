package indexing

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

func TestScannerIndexesMixedMediaAndIgnoresOtherFiles(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "2026", "kids"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "2026", "kids", "photo.jpg"))
	writeFile(t, filepath.Join(root, "2026", "kids", "clip.mp4"))
	writeFile(t, filepath.Join(root, "2026", "kids", "notes.txt"))

	repo := &fakeIndexRepository{}
	scanner := NewScanner(root, repo)

	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result.ScannedFiles != 2 || result.IndexedFiles != 2 || result.DeletedFiles != 0 {
		t.Fatalf("scan result = %#v", result)
	}
	if len(repo.items) != 2 {
		t.Fatalf("items len = %d", len(repo.items))
	}
	if repo.items["2026/kids/photo.jpg"].Kind != domainmedia.KindPhoto {
		t.Fatalf("photo item = %#v", repo.items["2026/kids/photo.jpg"])
	}
	if repo.items["2026/kids/clip.mp4"].Kind != domainmedia.KindVideo {
		t.Fatalf("video item = %#v", repo.items["2026/kids/clip.mp4"])
	}
}

func TestScannerDeletesMissingMedia(t *testing.T) {
	root := t.TempDir()
	photoPath := filepath.Join(root, "photo.jpg")
	writeFile(t, photoPath)

	repo := &fakeIndexRepository{}
	scanner := NewScanner(root, repo)
	if _, err := scanner.Scan(context.Background()); err != nil {
		t.Fatal(err)
	}

	if err := os.Remove(photoPath); err != nil {
		t.Fatal(err)
	}
	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result.DeletedFiles != 1 {
		t.Fatalf("deleted = %d", result.DeletedFiles)
	}
}

func TestScannerSkipsHiddenAndNASSystemDirectories(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "visible.jpg"))
	if err := os.MkdirAll(filepath.Join(root, "@eaDir"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, ".hidden"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "@eaDir", "ignored.jpg"))
	writeFile(t, filepath.Join(root, ".hidden", "ignored.jpg"))

	repo := &fakeIndexRepository{}
	scanner := NewScanner(root, repo)

	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result.ScannedFiles != 1 {
		t.Fatalf("scanned = %d", result.ScannedFiles)
	}
	if _, ok := repo.items["visible.jpg"]; !ok {
		t.Fatalf("visible item missing: %#v", repo.items)
	}
}

func TestScannerUsesCapturedAtForSortTime(t *testing.T) {
	root := t.TempDir()
	photoPath := filepath.Join(root, "photo.jpg")
	writeFile(t, photoPath)
	capturedAt := time.Unix(300, 0).UTC()

	repo := &fakeIndexRepository{}
	scanner := NewScannerWithMetadata(root, repo, fakeMetadataExtractor{
		capturedAt: &capturedAt,
	})

	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	item := repo.items["photo.jpg"]
	if item.CapturedAt == nil || !item.CapturedAt.Equal(capturedAt) {
		t.Fatalf("captured at = %#v", item.CapturedAt)
	}
	if !item.SortTime.Equal(capturedAt) {
		t.Fatalf("sort time = %v, want %v", item.SortTime, capturedAt)
	}
	if result.MetadataExtracted != 1 || result.MetadataMissing != 0 || result.MetadataFailed != 0 || result.MetadataFallback != 0 {
		t.Fatalf("metadata result = %#v", result)
	}
}

func TestScannerFallsBackToModifiedWhenMetadataFails(t *testing.T) {
	root := t.TempDir()
	photoPath := filepath.Join(root, "photo.jpg")
	writeFile(t, photoPath)

	repo := &fakeIndexRepository{}
	scanner := NewScannerWithMetadata(root, repo, fakeMetadataExtractor{
		err: os.ErrInvalid,
	})

	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	item := repo.items["photo.jpg"]
	if item.CapturedAt != nil {
		t.Fatalf("captured at = %#v", item.CapturedAt)
	}
	if !item.SortTime.Equal(item.Modified) {
		t.Fatalf("sort time = %v, want modified %v", item.SortTime, item.Modified)
	}
	if result.MetadataExtracted != 0 || result.MetadataMissing != 0 || result.MetadataFailed != 1 || result.MetadataFallback != 1 {
		t.Fatalf("metadata result = %#v", result)
	}
}

func TestScannerCountsMissingMetadataFallback(t *testing.T) {
	root := t.TempDir()
	photoPath := filepath.Join(root, "photo.jpg")
	writeFile(t, photoPath)

	repo := &fakeIndexRepository{}
	scanner := NewScannerWithMetadata(root, repo, fakeMetadataExtractor{})

	result, err := scanner.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	item := repo.items["photo.jpg"]
	if item.CapturedAt != nil {
		t.Fatalf("captured at = %#v", item.CapturedAt)
	}
	if !item.SortTime.Equal(item.Modified) {
		t.Fatalf("sort time = %v, want modified %v", item.SortTime, item.Modified)
	}
	if result.MetadataExtracted != 0 || result.MetadataMissing != 1 || result.MetadataFailed != 0 || result.MetadataFallback != 1 {
		t.Fatalf("metadata result = %#v", result)
	}
}

type fakeIndexRepository struct {
	items map[string]domainmedia.Item
}

func (r *fakeIndexRepository) Upsert(ctx context.Context, item domainmedia.Item) (bool, error) {
	if r.items == nil {
		r.items = make(map[string]domainmedia.Item)
	}
	previous, exists := r.items[item.MediaPath]
	r.items[item.MediaPath] = item
	return !exists ||
		previous.Size != item.Size ||
		!previous.Modified.Equal(item.Modified) ||
		!previous.SortTime.Equal(item.SortTime) ||
		!equalTimePointers(previous.CapturedAt, item.CapturedAt), nil
}

func (r *fakeIndexRepository) DeleteMissing(ctx context.Context, seenIDs map[string]struct{}) (int, error) {
	deleted := 0
	for mediaPath, item := range r.items {
		if _, ok := seenIDs[item.ID]; !ok {
			delete(r.items, mediaPath)
			deleted++
		}
	}
	return deleted, nil
}

func writeFile(t *testing.T, path string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(time.Now().String()), 0o644); err != nil {
		t.Fatal(err)
	}
}

type fakeMetadataExtractor struct {
	capturedAt *time.Time
	err        error
}

func (e fakeMetadataExtractor) Extract(context.Context, domainmedia.Item, string) (ExtractedMetadata, error) {
	return ExtractedMetadata{CapturedAt: e.capturedAt}, e.err
}

func equalTimePointers(left *time.Time, right *time.Time) bool {
	if left == nil || right == nil {
		return left == right
	}
	return left.Equal(*right)
}
