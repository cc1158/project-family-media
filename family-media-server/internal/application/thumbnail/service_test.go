package thumbnail

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	domainmedia "family-media-server/internal/domain/media"
)

func TestGeneratePendingUpdatesReadyAndFailedStatuses(t *testing.T) {
	root := t.TempDir()
	cache := t.TempDir()
	repository := &fakeRepository{
		items: []domainmedia.Item{
			{ID: "abcd1", Kind: domainmedia.KindPhoto, MediaPath: "ready.jpg"},
			{ID: "abcd2", Kind: domainmedia.KindVideo, MediaPath: "failed.mp4"},
		},
	}
	generator := fakeGenerator{
		errors: map[string]error{"failed.mp4": errors.New("boom")},
	}
	service := NewService(root, cache, generator, repository)

	result, err := service.GeneratePending(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if result.Pending != 2 || result.Generated != 1 || result.Failed != 1 {
		t.Fatalf("result = %#v", result)
	}
	if len(result.Failures) != 1 || result.Failures[0].Code != "thumbnail_generation_failed" {
		t.Fatalf("failures = %#v", result.Failures)
	}
	if repository.status["abcd1"] != domainmedia.ThumbnailReady {
		t.Fatalf("ready status = %q", repository.status["abcd1"])
	}
	if repository.status["abcd2"] != domainmedia.ThumbnailFailed {
		t.Fatalf("failed status = %q", repository.status["abcd2"])
	}
	if repository.paths["abcd1"] != filepath.Join("ab", "cd", "abcd1.jpg") {
		t.Fatalf("thumbnail path = %q", repository.paths["abcd1"])
	}
}

func TestGeneratePendingRepairsMissingReadyThumbnail(t *testing.T) {
	item := domainmedia.Item{
		ID:              "abcd1",
		Kind:            domainmedia.KindPhoto,
		MediaPath:       "photo.jpg",
		ThumbnailStatus: domainmedia.ThumbnailReady,
		ThumbnailPath:   filepath.Join("ab", "cd", "abcd1.jpg"),
	}
	repository := &fakeRepository{
		items:      []domainmedia.Item{item},
		readyItems: []domainmedia.Item{item},
	}
	service := NewService(t.TempDir(), t.TempDir(), fakeGenerator{}, repository)

	result, err := service.GeneratePending(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if result.Pending != 1 || result.Generated != 1 {
		t.Fatalf("result = %#v", result)
	}
	if repository.status[item.ID] != domainmedia.ThumbnailReady {
		t.Fatalf("status = %q", repository.status[item.ID])
	}
}

func TestGeneratePendingDrainsEveryBatch(t *testing.T) {
	repository := &fakeRepository{items: []domainmedia.Item{
		{ID: "abcd1", Kind: domainmedia.KindPhoto, MediaPath: "1.jpg"},
		{ID: "abcd2", Kind: domainmedia.KindPhoto, MediaPath: "2.jpg"},
		{ID: "abcd3", Kind: domainmedia.KindPhoto, MediaPath: "3.jpg"},
	}}
	service := NewService(t.TempDir(), t.TempDir(), fakeGenerator{}, repository)

	result, err := service.GeneratePending(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if result.Pending != 3 || result.Generated != 3 {
		t.Fatalf("result = %#v", result)
	}
}

func TestGeneratePendingRetriesHistoricalFailuresOnlyOncePerServiceLifetime(t *testing.T) {
	item := domainmedia.Item{
		ID:              "abcd1",
		Kind:            domainmedia.KindPhoto,
		MediaPath:       "photo.heic",
		ThumbnailStatus: domainmedia.ThumbnailFailed,
	}
	repository := &fakeRepository{
		items:       []domainmedia.Item{item},
		failedItems: []domainmedia.Item{item},
	}
	generator := fakeGenerator{errors: map[string]error{"photo.heic": errors.New("still broken")}}
	service := NewService(t.TempDir(), t.TempDir(), generator, repository)

	first, err := service.GeneratePending(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if first.Pending != 1 || first.Failed != 1 {
		t.Fatalf("first result = %#v", first)
	}

	second, err := service.GeneratePending(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if second.Pending != 0 || second.Failed != 0 {
		t.Fatalf("second result = %#v", second)
	}
}

func TestRegenerateUsesTimeOffsetAndDeletesOldThumbnail(t *testing.T) {
	root := t.TempDir()
	cache := t.TempDir()
	oldPath := filepath.Join(cache, "ab", "cd", "abcd1.jpg")
	if err := os.MkdirAll(filepath.Dir(oldPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(oldPath, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}

	repository := &fakeRepository{
		byID: map[string]domainmedia.Item{
			"abcd1": {ID: "abcd1", Kind: domainmedia.KindVideo, MediaPath: "video.mp4", ThumbnailPath: filepath.Join("ab", "cd", "abcd1.jpg")},
		},
	}
	generator := &fakeTimedGenerator{}
	service := NewService(root, cache, generator, repository)

	item, err := service.Regenerate(context.Background(), "abcd1", WithTimeOffsetSeconds(12))
	if err != nil {
		t.Fatal(err)
	}

	if item.ThumbnailStatus != domainmedia.ThumbnailReady {
		t.Fatalf("item = %#v", item)
	}
	if _, err := os.Stat(oldPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("old thumbnail still exists or unexpected error: %v", err)
	}
	if generator.offset != 12 {
		t.Fatalf("offset = %d", generator.offset)
	}
}

func TestRegenerateMissingMedia(t *testing.T) {
	service := NewService(t.TempDir(), t.TempDir(), fakeGenerator{}, &fakeRepository{})

	_, err := service.Regenerate(context.Background(), "missing")
	if !errors.Is(err, domainmedia.ErrNotFound) {
		t.Fatalf("err = %v", err)
	}
}

type fakeGenerator struct {
	errors map[string]error
}

func (g fakeGenerator) Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	return g.errors[item.MediaPath]
}

type fakeTimedGenerator struct {
	offset int
}

func (g *fakeTimedGenerator) Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error {
	return nil
}

func (g *fakeTimedGenerator) GenerateAt(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string, timeOffsetSeconds int) error {
	g.offset = timeOffsetSeconds
	return nil
}

type fakeRepository struct {
	items       []domainmedia.Item
	readyItems  []domainmedia.Item
	failedItems []domainmedia.Item
	byID        map[string]domainmedia.Item
	status      map[string]domainmedia.ThumbnailStatus
	paths       map[string]string
}

func (r *fakeRepository) GetByID(ctx context.Context, id string) (domainmedia.Item, error) {
	item, ok := r.byID[id]
	if !ok {
		return domainmedia.Item{}, domainmedia.ErrNotFound
	}
	return item, nil
}

func (r *fakeRepository) ListPendingThumbnails(ctx context.Context, limit int) ([]domainmedia.Item, error) {
	items := make([]domainmedia.Item, 0, limit)
	for _, item := range r.items {
		status, updated := r.status[item.ID]
		if updated && status != domainmedia.ThumbnailPending {
			continue
		}
		items = append(items, item)
		if len(items) == limit {
			break
		}
	}
	return items, nil
}

func (r *fakeRepository) ListReadyThumbnails(ctx context.Context) ([]domainmedia.Item, error) {
	return r.readyItems, nil
}

func (r *fakeRepository) ListFailedThumbnails(ctx context.Context) ([]domainmedia.Item, error) {
	return r.failedItems, nil
}

func (r *fakeRepository) UpdateThumbnail(ctx context.Context, id string, status domainmedia.ThumbnailStatus, thumbnailPath string, lastError string) error {
	if r.status == nil {
		r.status = make(map[string]domainmedia.ThumbnailStatus)
	}
	if r.paths == nil {
		r.paths = make(map[string]string)
	}
	r.status[id] = status
	r.paths[id] = thumbnailPath
	return nil
}
