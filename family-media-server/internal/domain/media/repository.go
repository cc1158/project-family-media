package media

import (
	"context"
	"errors"
	"time"
)

var ErrInvalidCursor = errors.New("invalid cursor")
var ErrInvalidContainer = errors.New("invalid container")
var ErrInvalidGroup = errors.New("invalid group")
var ErrInvalidSort = errors.New("invalid sort")
var ErrInvalidTimeZone = errors.New("invalid time zone")
var ErrInvalidBucket = errors.New("invalid timeline bucket")
var ErrNotFound = errors.New("not found")

type Sort string
type Group string

const (
	SortCapturedDesc Sort = "captured_desc"
	SortCapturedAsc  Sort = "captured_asc"
	SortModifiedDesc Sort = "modified_desc"
	SortIndexedDesc  Sort = "indexed_desc"
	SortNameAsc      Sort = "name_asc"
	SortNameDesc     Sort = "name_desc"
)

const (
	GroupMonth Group = "month"
)

type ListQuery struct {
	Kind   Kind
	Limit  int
	Cursor string
	Sort   Sort
	Group  Group
}

type Page struct {
	Items      []Item         `json:"items"`
	Groups     []GroupSection `json:"groups,omitempty"`
	NextCursor string         `json:"nextCursor"`
	HasMore    bool           `json:"hasMore"`
}

type GroupSection struct {
	Key        string `json:"key"`
	Title      string `json:"title"`
	StartIndex int    `json:"startIndex"`
	Count      int    `json:"count"`
}

type MediaListRepository interface {
	List(ctx context.Context, query ListQuery) (Page, error)
}

type DirectoryBrowseRepository interface {
	ListDirectoryPaths(ctx context.Context, scope MediaScope) ([]string, error)
	SummarizeScope(ctx context.Context, scope MediaScope) (ScopeSummary, bool, error)
	ListDirect(ctx context.Context, query DirectListQuery) (Page, error)
}

type TimelineRepository interface {
	WalkTimelineMetadata(ctx context.Context, scope MediaScope, visit func(TimelineMetadata) error) error
	ListTimeline(ctx context.Context, query TimelineListQuery) (Page, error)
}

type CatalogRepository interface {
	MediaListRepository
	DirectoryBrowseRepository
	TimelineRepository
}

// MediaScope describes either a recursive folder subtree or the virtual
// unclassified collection. DirectoryPath always uses slash-separated paths.
type MediaScope struct {
	Kind          Kind
	DirectoryPath string
	Unclassified  bool
	Recursive     bool
}

type ScopeSummary struct {
	Newest Item
	Cover  *Item
}

type PageKey struct {
	ValueInt64 int64
	ValueText  string
	ID         string
}

type DirectListQuery struct {
	Scope MediaScope
	Limit int
	Sort  Sort
	After *PageKey
}

type TimelineMetadata struct {
	SortTime        time.Time
	ThumbnailStatus ThumbnailStatus
	ThumbnailPath   string
}

type TimelineListQuery struct {
	Scope MediaScope
	Start time.Time
	End   time.Time
	Limit int
	Sort  TimelineSort
	After *PageKey
}

type IndexRepository interface {
	Upsert(ctx context.Context, item Item) (bool, error)
	DeleteMissing(ctx context.Context, seenIDs map[string]struct{}) (int, error)
}

type ThumbnailRepository interface {
	GetByID(ctx context.Context, id string) (Item, error)
	ListPendingThumbnails(ctx context.Context, limit int) ([]Item, error)
	ListReadyThumbnails(ctx context.Context) ([]Item, error)
	ListFailedThumbnails(ctx context.Context) ([]Item, error)
	UpdateThumbnail(ctx context.Context, id string, status ThumbnailStatus, thumbnailPath string, lastError string) error
}

// GeneratedDataRepository clears only server-owned index records. It must never
// remove files from the configured media library.
type GeneratedDataRepository interface {
	ClearGeneratedData(ctx context.Context) error
}
