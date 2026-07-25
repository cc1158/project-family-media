package sqlite

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"strings"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

type scanner interface {
	Scan(dest ...any) error
}

func scanItem(row scanner) (domainmedia.Item, error) {
	var item domainmedia.Item
	var kind string
	var status string
	var modifiedUnixNano int64
	var capturedAtUnixNano sql.NullInt64
	var sortUnixNano int64
	var indexedUnixNano int64
	if err := row.Scan(&item.ID, &kind, &item.Name, &item.MediaPath, &item.Size, &modifiedUnixNano, &capturedAtUnixNano, &sortUnixNano, &indexedUnixNano, &status, &item.ThumbnailPath, &item.LastError); err != nil {
		return domainmedia.Item{}, err
	}
	item.Kind = domainmedia.Kind(kind)
	item.Modified = time.Unix(0, modifiedUnixNano).UTC()
	if capturedAtUnixNano.Valid {
		capturedAt := time.Unix(0, capturedAtUnixNano.Int64).UTC()
		item.CapturedAt = &capturedAt
	}
	item.SortTime = time.Unix(0, sortUnixNano).UTC()
	item.IndexedAt = time.Unix(0, indexedUnixNano).UTC()
	item.ThumbnailStatus = domainmedia.ThumbnailStatus(status)
	return item, nil
}

type cursorValue struct {
	Sort             domainmedia.Sort `json:"sort,omitempty"`
	SortUnixNano     int64            `json:"sortUnixNano"`
	ModifiedUnixNano int64            `json:"modifiedUnixNano,omitempty"`
	IndexedUnixNano  int64            `json:"indexedUnixNano,omitempty"`
	Name             string           `json:"name,omitempty"`
	ID               string           `json:"id"`
}

func encodeCursor(value cursorValue) string {
	payload, _ := json.Marshal(value)
	return base64.RawURLEncoding.EncodeToString(payload)
}

func decodeCursor(raw string, sortMode listSort) (*cursorValue, error) {
	if raw == "" {
		return nil, nil
	}
	payload, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return nil, domainmedia.ErrInvalidCursor
	}
	var value cursorValue
	if err := json.Unmarshal(payload, &value); err != nil {
		return nil, domainmedia.ErrInvalidCursor
	}
	if value.Sort != "" && value.Sort != sortMode.name {
		return nil, domainmedia.ErrInvalidCursor
	}
	if value.SortUnixNano == 0 {
		value.SortUnixNano = value.ModifiedUnixNano
	}
	if value.SortUnixNano == 0 {
		value.SortUnixNano = value.IndexedUnixNano
	}
	if value.ID == "" {
		return nil, domainmedia.ErrInvalidCursor
	}
	switch sortMode.name {
	case domainmedia.SortNameAsc:
		if value.Name == "" {
			return nil, domainmedia.ErrInvalidCursor
		}
	default:
		if value.SortUnixNano == 0 {
			return nil, domainmedia.ErrInvalidCursor
		}
	}
	return &value, nil
}

type listSort struct {
	name domainmedia.Sort
}

type listGroup struct {
	name domainmedia.Group
}

func normalizeSort(sort domainmedia.Sort) (listSort, error) {
	if sort == "" {
		return listSort{name: domainmedia.SortCapturedDesc}, nil
	}
	switch sort {
	case domainmedia.SortCapturedDesc, domainmedia.SortModifiedDesc, domainmedia.SortIndexedDesc, domainmedia.SortNameAsc:
		return listSort{name: sort}, nil
	default:
		return listSort{}, domainmedia.ErrInvalidSort
	}
}

func normalizeGroup(group domainmedia.Group, sortMode listSort) (listGroup, error) {
	if group == "" {
		return listGroup{}, nil
	}
	if group != domainmedia.GroupMonth {
		return listGroup{}, domainmedia.ErrInvalidGroup
	}
	if sortMode.name == domainmedia.SortNameAsc {
		return listGroup{}, domainmedia.ErrInvalidGroup
	}
	return listGroup{name: group}, nil
}

func (s listSort) orderBy() string {
	switch s.name {
	case domainmedia.SortModifiedDesc:
		return "modified_unix_nano DESC, id DESC"
	case domainmedia.SortIndexedDesc:
		return "indexed_unix_nano DESC, id DESC"
	case domainmedia.SortNameAsc:
		return "lower(name) ASC, id ASC"
	default:
		return "sort_unix_nano DESC, id DESC"
	}
}

func (s listSort) cursorWhere(cursor *cursorValue) (string, []any) {
	switch s.name {
	case domainmedia.SortModifiedDesc:
		return "(modified_unix_nano < ? OR (modified_unix_nano = ? AND id < ?))", []any{cursor.SortUnixNano, cursor.SortUnixNano, cursor.ID}
	case domainmedia.SortIndexedDesc:
		return "(indexed_unix_nano < ? OR (indexed_unix_nano = ? AND id < ?))", []any{cursor.SortUnixNano, cursor.SortUnixNano, cursor.ID}
	case domainmedia.SortNameAsc:
		return "(lower(name) > ? OR (lower(name) = ? AND id > ?))", []any{cursor.Name, cursor.Name, cursor.ID}
	default:
		return "(sort_unix_nano < ? OR (sort_unix_nano = ? AND id < ?))", []any{cursor.SortUnixNano, cursor.SortUnixNano, cursor.ID}
	}
}

func (s listSort) cursorFor(item domainmedia.Item) cursorValue {
	value := cursorValue{
		Sort: s.name,
		ID:   item.ID,
	}
	switch s.name {
	case domainmedia.SortModifiedDesc:
		value.SortUnixNano = item.Modified.UnixNano()
	case domainmedia.SortIndexedDesc:
		value.SortUnixNano = item.IndexedAt.UnixNano()
	case domainmedia.SortNameAsc:
		value.Name = strings.ToLower(item.Name)
	default:
		value.SortUnixNano = item.SortTime.UnixNano()
	}
	return value
}

func (g listGroup) groups(items []domainmedia.Item, sortMode listSort) []domainmedia.GroupSection {
	if g.name == "" || len(items) == 0 {
		return nil
	}

	groups := make([]domainmedia.GroupSection, 0)
	for index, item := range items {
		groupTime := sortMode.groupTime(item)
		if groupTime.IsZero() {
			continue
		}
		key := groupTime.Format("2006-01")
		if len(groups) > 0 && groups[len(groups)-1].Key == key {
			groups[len(groups)-1].Count++
			continue
		}
		groups = append(groups, domainmedia.GroupSection{
			Key:        key,
			Title:      key,
			StartIndex: index,
			Count:      1,
		})
	}
	return groups
}

func (s listSort) groupTime(item domainmedia.Item) time.Time {
	switch s.name {
	case domainmedia.SortModifiedDesc:
		return item.Modified
	case domainmedia.SortIndexedDesc:
		return item.IndexedAt
	default:
		return item.SortTime
	}
}
