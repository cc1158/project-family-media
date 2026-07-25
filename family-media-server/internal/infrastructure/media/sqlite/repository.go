package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"sync"
	"time"

	modernsqlite "modernc.org/sqlite"

	domainmedia "family-media-server/internal/domain/media"
)

const defaultLimit = 50
const maxLimit = 100

const naturalCollationName = "family_natural"

var (
	registerNaturalCollationOnce sync.Once
	registerNaturalCollationErr  error
)

type Repository struct {
	db           *sql.DB
	indexRebuilt bool
}

func Open(path string) (*Repository, error) {
	registerNaturalCollationOnce.Do(func() {
		registerNaturalCollationErr = modernsqlite.RegisterCollationUtf8(
			naturalCollationName,
			domainmedia.NaturalCompare,
		)
	})
	if registerNaturalCollationErr != nil {
		return nil, fmt.Errorf("register natural collation: %w", registerNaturalCollationErr)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create sqlite directory: %w", err)
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite database: %w", err)
	}
	db.SetMaxOpenConns(1)

	repo := &Repository{db: db}
	rebuilt, err := repo.ensureCurrentSchema(context.Background())
	if err != nil {
		_ = db.Close()
		return nil, err
	}
	repo.indexRebuilt = rebuilt
	return repo, nil
}

func (r *Repository) Close() error {
	return r.db.Close()
}

func (r *Repository) IndexRebuilt() bool {
	return r.indexRebuilt
}

func (r *Repository) List(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	limit := normalizeLimit(query.Limit)
	sortMode, err := normalizeSort(query.Sort)
	if err != nil {
		return domainmedia.Page{}, err
	}
	groupMode, err := normalizeGroup(query.Group, sortMode)
	if err != nil {
		return domainmedia.Page{}, err
	}

	cursor, err := decodeCursor(query.Cursor, sortMode)
	if err != nil {
		return domainmedia.Page{}, err
	}

	args := []any{}
	where := "WHERE 1=1"
	if query.Kind != "" {
		where += " AND kind = ?"
		args = append(args, string(query.Kind))
	}
	if cursor != nil {
		cursorWhere, cursorArgs := sortMode.cursorWhere(cursor)
		where += " AND " + cursorWhere
		args = append(args, cursorArgs...)
	}
	args = append(args, limit+1)

	rows, err := r.db.QueryContext(ctx, `
		SELECT id, kind, name, media_path, size, modified_unix_nano, captured_at_unix_nano, sort_unix_nano, indexed_unix_nano, thumbnail_status, thumbnail_path, last_error
		FROM media_items
		`+where+`
		ORDER BY `+sortMode.orderBy()+`
		LIMIT ?`, args...)
	if err != nil {
		return domainmedia.Page{}, fmt.Errorf("list media: %w", err)
	}
	defer rows.Close()

	items := make([]domainmedia.Item, 0, limit+1)
	for rows.Next() {
		item, err := scanItem(rows)
		if err != nil {
			return domainmedia.Page{}, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return domainmedia.Page{}, err
	}

	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}

	nextCursor := ""
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		nextCursor = encodeCursor(sortMode.cursorFor(last))
	}

	return domainmedia.Page{Items: items, Groups: groupMode.groups(items, sortMode), NextCursor: nextCursor, HasMore: hasMore}, nil
}

func (r *Repository) Upsert(ctx context.Context, item domainmedia.Item) (bool, error) {
	nowTime := time.Now().UTC()
	now := nowTime.Format(time.RFC3339Nano)
	sortTime := item.SortTime
	if sortTime.IsZero() {
		sortTime = item.Modified
	}
	var capturedAtUnixNano any
	if item.CapturedAt != nil {
		capturedAtUnixNano = item.CapturedAt.UnixNano()
	}
	result, err := r.db.ExecContext(ctx, `
		INSERT INTO media_items (
			id, kind, name, media_path, directory_path, size, modified_unix_nano, captured_at_unix_nano, sort_unix_nano,
			thumbnail_status, thumbnail_path, last_error, indexed_at, indexed_unix_nano, created_at, updated_at
		)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			kind = excluded.kind,
			name = excluded.name,
			media_path = excluded.media_path,
			directory_path = excluded.directory_path,
			size = excluded.size,
			modified_unix_nano = excluded.modified_unix_nano,
			captured_at_unix_nano = excluded.captured_at_unix_nano,
			sort_unix_nano = excluded.sort_unix_nano,
			thumbnail_status = CASE
				WHEN media_items.size != excluded.size OR media_items.modified_unix_nano != excluded.modified_unix_nano
				THEN ?
				ELSE media_items.thumbnail_status
			END,
			thumbnail_path = CASE
				WHEN media_items.size != excluded.size OR media_items.modified_unix_nano != excluded.modified_unix_nano
				THEN ''
				ELSE media_items.thumbnail_path
			END,
			last_error = CASE
				WHEN media_items.size != excluded.size OR media_items.modified_unix_nano != excluded.modified_unix_nano
				THEN ''
				ELSE media_items.last_error
			END,
			updated_at = excluded.updated_at
		WHERE
			media_items.kind != excluded.kind OR
			media_items.name != excluded.name OR
			media_items.media_path != excluded.media_path OR
			media_items.directory_path != excluded.directory_path OR
			media_items.size != excluded.size OR
			media_items.modified_unix_nano != excluded.modified_unix_nano OR
			media_items.captured_at_unix_nano IS NOT excluded.captured_at_unix_nano OR
			media_items.sort_unix_nano != excluded.sort_unix_nano
	`, item.ID, string(item.Kind), item.Name, item.MediaPath, mediaDirectoryPath(item.MediaPath), item.Size, item.Modified.UnixNano(),
		capturedAtUnixNano, sortTime.UnixNano(), string(domainmedia.ThumbnailPending), item.ThumbnailPath, item.LastError, now, nowTime.UnixNano(), now, now, string(domainmedia.ThumbnailPending))
	if err != nil {
		return false, fmt.Errorf("upsert media item: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return false, nil
	}
	return affected > 0, nil
}

func mediaDirectoryPath(mediaPath string) string {
	directory := path.Dir(mediaPath)
	if directory == "." {
		return ""
	}
	return directory
}

func (r *Repository) DeleteMissing(ctx context.Context, seenIDs map[string]struct{}) (int, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id FROM media_items`)
	if err != nil {
		return 0, fmt.Errorf("list existing ids: %w", err)
	}
	defer rows.Close()

	missing := make([]string, 0)
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return 0, err
		}
		if _, ok := seenIDs[id]; !ok {
			missing = append(missing, id)
		}
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}

	for _, id := range missing {
		if _, err := r.db.ExecContext(ctx, `DELETE FROM media_items WHERE id = ?`, id); err != nil {
			return 0, fmt.Errorf("delete missing media item: %w", err)
		}
	}
	return len(missing), nil
}

func (r *Repository) ListPendingThumbnails(ctx context.Context, limit int) ([]domainmedia.Item, error) {
	limit = normalizeLimit(limit)

	rows, err := r.db.QueryContext(ctx, `
		SELECT id, kind, name, media_path, size, modified_unix_nano, captured_at_unix_nano, sort_unix_nano, indexed_unix_nano, thumbnail_status, thumbnail_path, last_error
		FROM media_items
		WHERE thumbnail_status = ?
		ORDER BY updated_at ASC
		LIMIT ?`, string(domainmedia.ThumbnailPending), limit)
	if err != nil {
		return nil, fmt.Errorf("list pending thumbnails: %w", err)
	}
	defer rows.Close()

	items := make([]domainmedia.Item, 0, limit)
	for rows.Next() {
		item, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *Repository) ListReadyThumbnails(ctx context.Context) ([]domainmedia.Item, error) {
	return r.listThumbnailsByStatus(ctx, domainmedia.ThumbnailReady)
}

func (r *Repository) ListFailedThumbnails(ctx context.Context) ([]domainmedia.Item, error) {
	return r.listThumbnailsByStatus(ctx, domainmedia.ThumbnailFailed)
}

func (r *Repository) listThumbnailsByStatus(ctx context.Context, status domainmedia.ThumbnailStatus) ([]domainmedia.Item, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, kind, name, media_path, size, modified_unix_nano, captured_at_unix_nano, sort_unix_nano, indexed_unix_nano, thumbnail_status, thumbnail_path, last_error
		FROM media_items
		WHERE thumbnail_status = ?`, string(status))
	if err != nil {
		return nil, fmt.Errorf("list %s thumbnails: %w", status, err)
	}
	defer rows.Close()

	items := make([]domainmedia.Item, 0)
	for rows.Next() {
		item, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *Repository) GetByID(ctx context.Context, id string) (domainmedia.Item, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT id, kind, name, media_path, size, modified_unix_nano, captured_at_unix_nano, sort_unix_nano, indexed_unix_nano, thumbnail_status, thumbnail_path, last_error
		FROM media_items
		WHERE id = ?`, id)
	item, err := scanItem(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return domainmedia.Item{}, domainmedia.ErrNotFound
		}
		return domainmedia.Item{}, fmt.Errorf("get media item: %w", err)
	}
	return item, nil
}

func (r *Repository) UpdateThumbnail(ctx context.Context, id string, status domainmedia.ThumbnailStatus, thumbnailPath string, lastError string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE media_items
		SET thumbnail_status = ?, thumbnail_path = ?, last_error = ?, updated_at = ?
		WHERE id = ?`, string(status), thumbnailPath, lastError, time.Now().UTC().Format(time.RFC3339Nano), id)
	if err != nil {
		return fmt.Errorf("update thumbnail: %w", err)
	}
	return nil
}

func (r *Repository) ClearGeneratedData(ctx context.Context) error {
	if _, err := r.db.ExecContext(ctx, `DELETE FROM media_items`); err != nil {
		return fmt.Errorf("clear media index: %w", err)
	}
	if _, err := r.db.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		return fmt.Errorf("checkpoint media index: %w", err)
	}
	if _, err := r.db.ExecContext(ctx, `VACUUM`); err != nil {
		return fmt.Errorf("compact media index: %w", err)
	}
	return nil
}

func normalizeLimit(limit int) int {
	if limit <= 0 {
		return defaultLimit
	}
	if limit > maxLimit {
		return maxLimit
	}
	return limit
}
