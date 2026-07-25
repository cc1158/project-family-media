package sqlite

import (
	"context"
	"database/sql"
	"fmt"
)

var currentMediaColumns = []string{
	"id",
	"kind",
	"name",
	"media_path",
	"directory_path",
	"size",
	"modified_unix_nano",
	"captured_at_unix_nano",
	"sort_unix_nano",
	"thumbnail_status",
	"thumbnail_path",
	"last_error",
	"indexed_at",
	"indexed_unix_nano",
	"created_at",
	"updated_at",
}

func (r *Repository) ensureCurrentSchema(ctx context.Context) (bool, error) {
	if _, err := r.db.ExecContext(ctx, `PRAGMA journal_mode = WAL`); err != nil {
		return false, fmt.Errorf("configure sqlite journal: %w", err)
	}
	if _, err := r.db.ExecContext(ctx, `PRAGMA busy_timeout = 5000`); err != nil {
		return false, fmt.Errorf("configure sqlite busy timeout: %w", err)
	}

	columns, err := r.mediaColumns(ctx)
	if err != nil {
		return false, err
	}
	rebuilt := len(columns) > 0 && !sameColumns(columns, currentMediaColumns)
	if rebuilt {
		if _, err := r.db.ExecContext(ctx, `DROP TABLE media_items`); err != nil {
			return false, fmt.Errorf("reset outdated media index: %w", err)
		}
	}
	if err := r.createCurrentSchema(ctx); err != nil {
		return false, err
	}
	return rebuilt, nil
}

func (r *Repository) mediaColumns(ctx context.Context) ([]string, error) {
	rows, err := r.db.QueryContext(ctx, `PRAGMA table_info(media_items)`)
	if err != nil {
		return nil, fmt.Errorf("inspect media index: %w", err)
	}
	defer rows.Close()
	columns := make([]string, 0)
	for rows.Next() {
		var cid, notNull, primaryKey int
		var name, columnType string
		var defaultValue sql.NullString
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			return nil, err
		}
		columns = append(columns, name)
	}
	return columns, rows.Err()
}

func sameColumns(actual, expected []string) bool {
	if len(actual) != len(expected) {
		return false
	}
	for index := range expected {
		if actual[index] != expected[index] {
			return false
		}
	}
	return true
}

func (r *Repository) createCurrentSchema(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS media_items (
			id TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			name TEXT NOT NULL,
			media_path TEXT NOT NULL UNIQUE,
			directory_path TEXT NOT NULL,
			size INTEGER NOT NULL,
			modified_unix_nano INTEGER NOT NULL,
			captured_at_unix_nano INTEGER,
			sort_unix_nano INTEGER NOT NULL,
			thumbnail_status TEXT NOT NULL,
			thumbnail_path TEXT NOT NULL DEFAULT '',
			last_error TEXT NOT NULL DEFAULT '',
			indexed_at TEXT NOT NULL,
			indexed_unix_nano INTEGER NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_list ON media_items(kind, sort_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_sort ON media_items(sort_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_modified ON media_items(modified_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_indexed ON media_items(indexed_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_name ON media_items(lower(name), id)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_thumbnail ON media_items(thumbnail_status, updated_at)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_directory_sort ON media_items(directory_path, kind, sort_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_directory_indexed ON media_items(directory_path, kind, indexed_unix_nano DESC, id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_media_items_directory_name ON media_items(directory_path, kind, name COLLATE family_natural, id)`,
	}
	for _, statement := range statements {
		if _, err := r.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("create media index: %w", err)
		}
	}
	return nil
}
