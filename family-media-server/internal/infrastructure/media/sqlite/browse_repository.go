package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

const maxCatalogLimit = 200

func (r *Repository) ListDirectoryPaths(ctx context.Context, scope domainmedia.MediaScope) ([]string, error) {
	where, args := scopeWhere(scope)
	rows, err := r.db.QueryContext(ctx, `
		SELECT DISTINCT directory_path
		FROM media_items
		`+where+`
		ORDER BY directory_path`, args...)
	if err != nil {
		return nil, fmt.Errorf("list directory paths: %w", err)
	}
	defer rows.Close()
	paths := make([]string, 0)
	for rows.Next() {
		var directory string
		if err := rows.Scan(&directory); err != nil {
			return nil, err
		}
		paths = append(paths, directory)
	}
	return paths, rows.Err()
}

func (r *Repository) SummarizeScope(ctx context.Context, scope domainmedia.MediaScope) (domainmedia.ScopeSummary, bool, error) {
	newest, ok, err := r.findScopeRepresentative(ctx, scope, false)
	if err != nil || !ok {
		return domainmedia.ScopeSummary{}, false, err
	}
	cover, hasCover, err := r.findScopeRepresentative(ctx, scope, true)
	if err != nil {
		return domainmedia.ScopeSummary{}, false, err
	}
	summary := domainmedia.ScopeSummary{Newest: newest}
	if hasCover {
		summary.Cover = &cover
	}
	return summary, true, nil
}

func (r *Repository) findScopeRepresentative(
	ctx context.Context,
	scope domainmedia.MediaScope,
	requireThumbnail bool,
) (domainmedia.Item, bool, error) {
	where, args := scopeWhere(scope)
	if requireThumbnail {
		where += " AND thumbnail_status = ? AND thumbnail_path != ''"
		args = append(args, string(domainmedia.ThumbnailReady))
	}
	row := r.db.QueryRowContext(ctx, itemSelect+where+` ORDER BY sort_unix_nano DESC, id DESC LIMIT 1`, args...)
	item, err := scanItem(row)
	if err == sql.ErrNoRows {
		return domainmedia.Item{}, false, nil
	}
	if err != nil {
		return domainmedia.Item{}, false, fmt.Errorf("summarize media scope: %w", err)
	}
	return item, true, nil
}

func (r *Repository) ListDirect(ctx context.Context, query domainmedia.DirectListQuery) (domainmedia.Page, error) {
	query.Scope.Recursive = false
	where, args := scopeWhere(query.Scope)
	orderBy, cursorWhere, cursorArgs, err := directSortSQL(query.Sort, query.After)
	if err != nil {
		return domainmedia.Page{}, err
	}
	where += cursorWhere
	args = append(args, cursorArgs...)
	limit := normalizeCatalogLimit(query.Limit)
	args = append(args, limit+1)
	rows, err := r.db.QueryContext(ctx, itemSelect+where+` ORDER BY `+orderBy+` LIMIT ?`, args...)
	if err != nil {
		return domainmedia.Page{}, fmt.Errorf("list direct media: %w", err)
	}
	page, err := scanPage(rows, limit)
	if err != nil {
		return domainmedia.Page{}, fmt.Errorf("read direct media page: %w", err)
	}
	return page, nil
}

func (r *Repository) WalkTimelineMetadata(
	ctx context.Context,
	scope domainmedia.MediaScope,
	visit func(domainmedia.TimelineMetadata) error,
) error {
	where, args := scopeWhere(scope)
	rows, err := r.db.QueryContext(ctx, `
		SELECT sort_unix_nano, thumbnail_status, thumbnail_path
		FROM media_items
		`+where+`
		ORDER BY sort_unix_nano DESC, id DESC`, args...)
	if err != nil {
		return fmt.Errorf("walk timeline metadata: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var unixNano int64
		var status domainmedia.ThumbnailStatus
		var thumbnailPath string
		if err := rows.Scan(&unixNano, &status, &thumbnailPath); err != nil {
			return err
		}
		if err := visit(domainmedia.TimelineMetadata{
			SortTime:        time.Unix(0, unixNano).UTC(),
			ThumbnailStatus: status,
			ThumbnailPath:   thumbnailPath,
		}); err != nil {
			return err
		}
	}
	return rows.Err()
}

func (r *Repository) ListTimeline(ctx context.Context, query domainmedia.TimelineListQuery) (domainmedia.Page, error) {
	where, args := scopeWhere(query.Scope)
	where += " AND sort_unix_nano >= ? AND sort_unix_nano < ?"
	args = append(args, query.Start.UnixNano(), query.End.UnixNano())
	orderBy, cursorWhere, cursorArgs := timelineSortSQL(query.Sort, query.After)
	where += cursorWhere
	args = append(args, cursorArgs...)
	limit := normalizeCatalogLimit(query.Limit)
	args = append(args, limit+1)
	rows, err := r.db.QueryContext(ctx, itemSelect+where+` ORDER BY `+orderBy+` LIMIT ?`, args...)
	if err != nil {
		return domainmedia.Page{}, fmt.Errorf("list timeline media: %w", err)
	}
	page, err := scanPage(rows, limit)
	if err != nil {
		return domainmedia.Page{}, fmt.Errorf("read timeline media page: %w", err)
	}
	return page, nil
}

const itemSelect = `
	SELECT id, kind, name, media_path, size, modified_unix_nano, captured_at_unix_nano,
		sort_unix_nano, indexed_unix_nano, thumbnail_status, thumbnail_path, last_error
	FROM media_items`

func scopeWhere(scope domainmedia.MediaScope) (string, []any) {
	clauses := []string{"1=1"}
	args := make([]any, 0, 3)
	if scope.Kind != "" {
		clauses = append(clauses, "kind = ?")
		args = append(args, string(scope.Kind))
	}
	switch {
	case scope.Unclassified:
		clauses = append(clauses, "directory_path = ''")
	case scope.Recursive && scope.DirectoryPath != "":
		clauses = append(clauses, "(directory_path = ? OR directory_path LIKE ? ESCAPE '\\')")
		args = append(args, scope.DirectoryPath, escapeLike(scope.DirectoryPath)+"/%")
	case !scope.Recursive:
		clauses = append(clauses, "directory_path = ?")
		args = append(args, scope.DirectoryPath)
	}
	return " WHERE " + strings.Join(clauses, " AND "), args
}

func escapeLike(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `%`, `\%`)
	return strings.ReplaceAll(value, `_`, `\_`)
}

func directSortSQL(sortMode domainmedia.Sort, after *domainmedia.PageKey) (string, string, []any, error) {
	if sortMode == "" {
		sortMode = domainmedia.SortCapturedDesc
	}
	var column, direction, collation string
	switch sortMode {
	case domainmedia.SortCapturedDesc:
		column, direction = "sort_unix_nano", "DESC"
	case domainmedia.SortCapturedAsc:
		column, direction = "sort_unix_nano", "ASC"
	case domainmedia.SortIndexedDesc:
		column, direction = "indexed_unix_nano", "DESC"
	case domainmedia.SortNameAsc:
		column, direction, collation = "name", "ASC", " COLLATE "+naturalCollationName
	case domainmedia.SortNameDesc:
		column, direction, collation = "name", "DESC", " COLLATE "+naturalCollationName
	default:
		return "", "", nil, domainmedia.ErrInvalidSort
	}
	orderBy := column + collation + " " + direction + ", id " + direction
	if after == nil {
		return orderBy, "", nil, nil
	}
	operator := "<"
	if direction == "ASC" {
		operator = ">"
	}
	if column == "name" {
		where := fmt.Sprintf(" AND (%s%s %s ? OR (%s%s = ? AND id %s ?))", column, collation, operator, column, collation, operator)
		return orderBy, where, []any{after.ValueText, after.ValueText, after.ID}, nil
	}
	where := fmt.Sprintf(" AND (%s %s ? OR (%s = ? AND id %s ?))", column, operator, column, operator)
	return orderBy, where, []any{after.ValueInt64, after.ValueInt64, after.ID}, nil
}

func timelineSortSQL(sortMode domainmedia.TimelineSort, after *domainmedia.PageKey) (string, string, []any) {
	direction, operator := "DESC", "<"
	if sortMode == domainmedia.TimelineSortCapturedAsc {
		direction, operator = "ASC", ">"
	}
	if after == nil {
		return "sort_unix_nano " + direction + ", id " + direction, "", nil
	}
	return "sort_unix_nano " + direction + ", id " + direction,
		fmt.Sprintf(" AND (sort_unix_nano %s ? OR (sort_unix_nano = ? AND id %s ?))", operator, operator),
		[]any{after.ValueInt64, after.ValueInt64, after.ID}
}

func scanPage(rows *sql.Rows, limit int) (domainmedia.Page, error) {
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
	return domainmedia.Page{Items: items, HasMore: hasMore}, nil
}

func normalizeCatalogLimit(limit int) int {
	if limit <= 0 {
		return defaultLimit
	}
	if limit > maxCatalogLimit {
		return maxCatalogLimit
	}
	return limit
}
