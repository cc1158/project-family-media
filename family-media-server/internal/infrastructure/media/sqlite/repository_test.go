package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

func TestRepositoryListsMediaWithCursorPagination(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	items := []domainmedia.Item{
		item("3", domainmedia.KindPhoto, "c.jpg", time.Unix(300, 0)),
		item("2", domainmedia.KindVideo, "b.mp4", time.Unix(200, 0)),
		item("1", domainmedia.KindPhoto, "a.jpg", time.Unix(100, 0)),
	}
	for _, item := range items {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	first, err := repo.List(ctx, domainmedia.ListQuery{Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 2 || !first.HasMore || first.NextCursor == "" {
		t.Fatalf("first page = %#v", first)
	}
	if first.Items[0].ID != "3" || first.Items[1].ID != "2" {
		t.Fatalf("first page order = %#v", first.Items)
	}

	second, err := repo.List(ctx, domainmedia.ListQuery{Limit: 2, Cursor: first.NextCursor})
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.HasMore {
		t.Fatalf("second page = %#v", second)
	}
	if second.Items[0].ID != "1" {
		t.Fatalf("second page item = %#v", second.Items[0])
	}
}

func TestRepositoryUsesIDAsStableSortTieBreaker(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	modified := time.Unix(100, 0)

	items := []domainmedia.Item{
		item("1", domainmedia.KindPhoto, "a.jpg", modified),
		item("3", domainmedia.KindPhoto, "c.jpg", modified),
		item("2", domainmedia.KindPhoto, "b.jpg", modified),
	}
	for _, item := range items {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	page, err := repo.List(ctx, domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 3 {
		t.Fatalf("items = %#v", page.Items)
	}
	if page.Items[0].ID != "3" || page.Items[1].ID != "2" || page.Items[2].ID != "1" {
		t.Fatalf("order = %#v", page.Items)
	}
}

func TestRepositoryListsBySortTime(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	oldFileNewCapture := item("captured", domainmedia.KindPhoto, "captured.jpg", time.Unix(100, 0))
	capturedAt := time.Unix(300, 0).UTC()
	oldFileNewCapture.CapturedAt = &capturedAt
	oldFileNewCapture.SortTime = capturedAt

	newFileOldCapture := item("modified", domainmedia.KindPhoto, "modified.jpg", time.Unix(200, 0))

	for _, item := range []domainmedia.Item{oldFileNewCapture, newFileOldCapture} {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	page, err := repo.List(ctx, domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("items = %#v", page.Items)
	}
	if page.Items[0].ID != "captured" || page.Items[0].CapturedAt == nil {
		t.Fatalf("first item = %#v", page.Items[0])
	}
	if got, want := page.Items[0].SortTime, capturedAt; !got.Equal(want) {
		t.Fatalf("sort time = %v, want %v", got, want)
	}
}

func TestRepositoryListsByModifiedTime(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	capturedFirst := item("captured", domainmedia.KindPhoto, "captured.jpg", time.Unix(100, 0))
	capturedAt := time.Unix(300, 0).UTC()
	capturedFirst.CapturedAt = &capturedAt
	capturedFirst.SortTime = capturedAt

	modifiedFirst := item("modified", domainmedia.KindPhoto, "modified.jpg", time.Unix(200, 0))

	for _, item := range []domainmedia.Item{capturedFirst, modifiedFirst} {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	page, err := repo.List(ctx, domainmedia.ListQuery{Sort: domainmedia.SortModifiedDesc})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("items = %#v", page.Items)
	}
	if page.Items[0].ID != "modified" {
		t.Fatalf("first item = %#v", page.Items[0])
	}
}

func TestRepositoryListsByNameWithCursorPagination(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	items := []domainmedia.Item{
		item("3", domainmedia.KindPhoto, "Charlie.jpg", time.Unix(300, 0)),
		item("1", domainmedia.KindPhoto, "alpha.jpg", time.Unix(100, 0)),
		item("2", domainmedia.KindPhoto, "bravo.jpg", time.Unix(200, 0)),
	}
	for _, item := range items {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	first, err := repo.List(ctx, domainmedia.ListQuery{Sort: domainmedia.SortNameAsc, Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 2 || !first.HasMore || first.NextCursor == "" {
		t.Fatalf("first page = %#v", first)
	}
	if first.Items[0].ID != "1" || first.Items[1].ID != "2" {
		t.Fatalf("first page order = %#v", first.Items)
	}

	second, err := repo.List(ctx, domainmedia.ListQuery{Sort: domainmedia.SortNameAsc, Limit: 2, Cursor: first.NextCursor})
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.Items[0].ID != "3" {
		t.Fatalf("second page = %#v", second)
	}
}

func TestRepositoryListsByIndexedTimeWithCursorPagination(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	items := []domainmedia.Item{
		item("old", domainmedia.KindPhoto, "old.jpg", time.Unix(300, 0)),
		item("new", domainmedia.KindPhoto, "new.jpg", time.Unix(100, 0)),
		item("middle", domainmedia.KindPhoto, "middle.jpg", time.Unix(200, 0)),
	}
	for _, item := range items {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}
	setIndexedUnixNano(t, repo, "old", 100)
	setIndexedUnixNano(t, repo, "middle", 200)
	setIndexedUnixNano(t, repo, "new", 300)

	first, err := repo.List(ctx, domainmedia.ListQuery{Sort: domainmedia.SortIndexedDesc, Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 2 || !first.HasMore || first.NextCursor == "" {
		t.Fatalf("first page = %#v", first)
	}
	if first.Items[0].ID != "new" || first.Items[1].ID != "middle" {
		t.Fatalf("first page order = %#v", first.Items)
	}

	second, err := repo.List(ctx, domainmedia.ListQuery{Sort: domainmedia.SortIndexedDesc, Limit: 2, Cursor: first.NextCursor})
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.Items[0].ID != "old" {
		t.Fatalf("second page = %#v", second)
	}
}

func TestRepositoryGroupsByMonth(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	items := []domainmedia.Item{
		item("may-2", domainmedia.KindPhoto, "may-2.jpg", time.Date(2026, 5, 20, 12, 0, 0, 0, time.UTC)),
		item("may-1", domainmedia.KindPhoto, "may-1.jpg", time.Date(2026, 5, 1, 12, 0, 0, 0, time.UTC)),
		item("apr-1", domainmedia.KindPhoto, "apr-1.jpg", time.Date(2026, 4, 30, 12, 0, 0, 0, time.UTC)),
	}
	for _, item := range items {
		if _, err := repo.Upsert(ctx, item); err != nil {
			t.Fatal(err)
		}
	}

	page, err := repo.List(ctx, domainmedia.ListQuery{Group: domainmedia.GroupMonth})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Groups) != 2 {
		t.Fatalf("groups = %#v", page.Groups)
	}
	if page.Groups[0].Key != "2026-05" || page.Groups[0].StartIndex != 0 || page.Groups[0].Count != 2 {
		t.Fatalf("first group = %#v", page.Groups[0])
	}
	if page.Groups[1].Key != "2026-04" || page.Groups[1].StartIndex != 2 || page.Groups[1].Count != 1 {
		t.Fatalf("second group = %#v", page.Groups[1])
	}
}

func TestRepositoryRejectsInvalidGroup(t *testing.T) {
	repo := openTestRepository(t)

	_, err := repo.List(context.Background(), domainmedia.ListQuery{Group: "day"})
	if err != domainmedia.ErrInvalidGroup {
		t.Fatalf("err = %v", err)
	}

	_, err = repo.List(context.Background(), domainmedia.ListQuery{Sort: domainmedia.SortNameAsc, Group: domainmedia.GroupMonth})
	if err != domainmedia.ErrInvalidGroup {
		t.Fatalf("err = %v", err)
	}
}

func TestRepositoryRejectsInvalidSort(t *testing.T) {
	repo := openTestRepository(t)

	_, err := repo.List(context.Background(), domainmedia.ListQuery{Sort: "size_desc"})
	if err != domainmedia.ErrInvalidSort {
		t.Fatalf("err = %v", err)
	}
}

func setIndexedUnixNano(t *testing.T, repo *Repository, id string, unixNano int64) {
	t.Helper()
	if _, err := repo.db.Exec(`UPDATE media_items SET indexed_unix_nano = ? WHERE id = ?`, unixNano, id); err != nil {
		t.Fatal(err)
	}
}

func TestRepositoryCreatesCurrentSchema(t *testing.T) {
	repo := openTestRepository(t)
	if repo.IndexRebuilt() {
		t.Fatal("fresh database should not be reported as rebuilt")
	}

	columns, err := repo.mediaColumns(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !sameColumns(columns, currentMediaColumns) {
		t.Fatalf("columns = %v, want %v", columns, currentMediaColumns)
	}
}

func TestRepositoryRebuildsOutdatedGeneratedIndex(t *testing.T) {
	path := filepath.Join(t.TempDir(), "media.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		CREATE TABLE media_items (
			id TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			name TEXT NOT NULL,
			media_path TEXT NOT NULL UNIQUE
		);
		INSERT INTO media_items (id, kind, name, media_path)
		VALUES ('outdated', 'photo', '旧索引.jpg', '家庭/旧索引.jpg');
	`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	repo, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repo.Close() })
	if !repo.IndexRebuilt() {
		t.Fatal("outdated generated index should be reported as rebuilt")
	}

	page, err := repo.List(context.Background(), domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("outdated generated items were not cleared: %#v", page.Items)
	}

	mediaItem := item("new", domainmedia.KindPhoto, "成长/幼儿园/新照片.jpg", time.Unix(100, 0))
	if _, err := repo.Upsert(context.Background(), mediaItem); err != nil {
		t.Fatal(err)
	}
	var directoryPath string
	if err := repo.db.QueryRow(`SELECT directory_path FROM media_items WHERE id = 'new'`).Scan(&directoryPath); err != nil {
		t.Fatal(err)
	}
	if directoryPath != "成长/幼儿园" {
		t.Fatalf("directory path = %q, want 成长/幼儿园", directoryPath)
	}
}

func TestRepositoryFiltersByKindAndUpdatesThumbnail(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	if _, err := repo.Upsert(ctx, item("photo", domainmedia.KindPhoto, "photo.jpg", time.Unix(100, 0))); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Upsert(ctx, item("video", domainmedia.KindVideo, "video.mp4", time.Unix(200, 0))); err != nil {
		t.Fatal(err)
	}
	if err := repo.UpdateThumbnail(ctx, "photo", domainmedia.ThumbnailReady, "ab/cd/photo.jpg", ""); err != nil {
		t.Fatal(err)
	}

	photos, err := repo.List(ctx, domainmedia.ListQuery{Kind: domainmedia.KindPhoto})
	if err != nil {
		t.Fatal(err)
	}
	if len(photos.Items) != 1 || photos.Items[0].ID != "photo" {
		t.Fatalf("photos = %#v", photos.Items)
	}
	if photos.Items[0].ThumbnailPath != "ab/cd/photo.jpg" || photos.Items[0].ThumbnailStatus != domainmedia.ThumbnailReady {
		t.Fatalf("photo thumbnail = %#v", photos.Items[0])
	}
}

func TestRepositoryDeleteMissing(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	if _, err := repo.Upsert(ctx, item("keep", domainmedia.KindPhoto, "keep.jpg", time.Unix(100, 0))); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Upsert(ctx, item("delete", domainmedia.KindPhoto, "delete.jpg", time.Unix(90, 0))); err != nil {
		t.Fatal(err)
	}

	deleted, err := repo.DeleteMissing(ctx, map[string]struct{}{"keep": struct{}{}})
	if err != nil {
		t.Fatal(err)
	}
	if deleted != 1 {
		t.Fatalf("deleted = %d", deleted)
	}

	page, err := repo.List(ctx, domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 || page.Items[0].ID != "keep" {
		t.Fatalf("items = %#v", page.Items)
	}
}

func TestRepositoryGetByID(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	if _, err := repo.Upsert(ctx, item("photo", domainmedia.KindPhoto, "photo.jpg", time.Unix(100, 0))); err != nil {
		t.Fatal(err)
	}

	found, err := repo.GetByID(ctx, "photo")
	if err != nil {
		t.Fatal(err)
	}
	if found.ID != "photo" || found.MediaPath != "photo.jpg" {
		t.Fatalf("found = %#v", found)
	}

	_, err = repo.GetByID(ctx, "missing")
	if err != domainmedia.ErrNotFound {
		t.Fatalf("err = %v", err)
	}
}

func TestRepositoryListPendingThumbnailsExcludesFailedItems(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()

	if _, err := repo.Upsert(ctx, item("pending", domainmedia.KindPhoto, "pending.jpg", time.Unix(100, 0))); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Upsert(ctx, item("failed", domainmedia.KindVideo, "failed.mp4", time.Unix(200, 0))); err != nil {
		t.Fatal(err)
	}
	if err := repo.UpdateThumbnail(ctx, "failed", domainmedia.ThumbnailFailed, "", "ffmpeg not found"); err != nil {
		t.Fatal(err)
	}

	items, err := repo.ListPendingThumbnails(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].ID != "pending" {
		t.Fatalf("pending items = %#v", items)
	}
}

func TestRepositoryClearGeneratedDataKeepsDatabaseReusable(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	if _, err := repo.Upsert(ctx, item("old", domainmedia.KindPhoto, "old.jpg", time.Unix(100, 0))); err != nil {
		t.Fatal(err)
	}

	if err := repo.ClearGeneratedData(ctx); err != nil {
		t.Fatal(err)
	}
	page, err := repo.List(ctx, domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("items after clear = %#v", page.Items)
	}

	if _, err := repo.Upsert(ctx, item("new", domainmedia.KindVideo, "new.mp4", time.Unix(200, 0))); err != nil {
		t.Fatalf("database not reusable after clear: %v", err)
	}
}

func openTestRepository(t *testing.T) *Repository {
	t.Helper()
	repo, err := Open(filepath.Join(t.TempDir(), "media.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = repo.Close()
	})
	return repo
}

func item(id string, kind domainmedia.Kind, mediaPath string, modified time.Time) domainmedia.Item {
	return domainmedia.Item{
		ID:              id,
		Kind:            kind,
		Name:            filepath.Base(mediaPath),
		MediaPath:       mediaPath,
		Size:            1,
		Modified:        modified.UTC(),
		ThumbnailStatus: domainmedia.ThumbnailPending,
	}
}
