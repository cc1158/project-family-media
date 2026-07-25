package media

import (
	"context"
	"path"
	"sort"
	"strings"
	"testing"

	domainmedia "family-media-server/internal/domain/media"
)

func TestCatalogServiceAttachesEscapedURLs(t *testing.T) {
	service := NewCatalogService(fakeRepository{
		page: domainmedia.Page{Items: []domainmedia.Item{{
			Name:          "holiday movie.mp4",
			MediaPath:     "kids/holiday movie.mp4",
			Kind:          domainmedia.KindVideo,
			ThumbnailPath: "ab/cd/thumb.jpg",
		}}},
	}, "http://localhost:8080")

	page, err := service.Videos(context.Background(), domainmedia.ListQuery{})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := page.Items[0].URL, "http://localhost:8080/media/original/kids/holiday%20movie.mp4"; got != want {
		t.Fatalf("URL = %q, want %q", got, want)
	}
	if got, want := page.Items[0].ThumbnailURL, "http://localhost:8080/media/thumbnails/ab/cd/thumb.jpg"; got != want {
		t.Fatalf("ThumbnailURL = %q, want %q", got, want)
	}
}

type fakeRepository struct {
	page domainmedia.Page
}

func (r fakeRepository) List(context.Context, domainmedia.ListQuery) (domainmedia.Page, error) {
	return r.page, nil
}

func (r fakeRepository) ListDirectoryPaths(_ context.Context, scope domainmedia.MediaScope) ([]string, error) {
	seen := make(map[string]struct{})
	for _, item := range r.scopedItems(scope) {
		seen[testMediaDirectory(item.MediaPath)] = struct{}{}
	}
	result := make([]string, 0, len(seen))
	for directory := range seen {
		result = append(result, directory)
	}
	sort.Strings(result)
	return result, nil
}

func (r fakeRepository) SummarizeScope(_ context.Context, scope domainmedia.MediaScope) (domainmedia.ScopeSummary, bool, error) {
	items := r.scopedItems(scope)
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].SortTime.Equal(items[j].SortTime) {
			return items[i].ID > items[j].ID
		}
		return items[i].SortTime.After(items[j].SortTime)
	})
	if len(items) == 0 {
		return domainmedia.ScopeSummary{}, false, nil
	}
	summary := domainmedia.ScopeSummary{Newest: items[0]}
	for _, item := range items {
		if item.ThumbnailStatus == domainmedia.ThumbnailReady && item.ThumbnailPath != "" {
			cover := item
			summary.Cover = &cover
			break
		}
	}
	return summary, true, nil
}

func (r fakeRepository) ListDirect(_ context.Context, query domainmedia.DirectListQuery) (domainmedia.Page, error) {
	query.Scope.Recursive = false
	items := r.scopedItems(query.Scope)
	sortBrowseEntries(items, query.Sort)
	start := 0
	if query.After != nil {
		start = len(items)
		for index, item := range items {
			if item.ID == query.After.ID {
				start = index + 1
				break
			}
		}
	}
	return fakePage(items, start, query.Limit), nil
}

func (r fakeRepository) WalkTimelineMetadata(_ context.Context, scope domainmedia.MediaScope, visit func(domainmedia.TimelineMetadata) error) error {
	items := r.scopedItems(scope)
	sort.SliceStable(items, func(i, j int) bool { return items[i].SortTime.After(items[j].SortTime) })
	for _, item := range items {
		if err := visit(domainmedia.TimelineMetadata{SortTime: item.SortTime, ThumbnailStatus: item.ThumbnailStatus, ThumbnailPath: item.ThumbnailPath}); err != nil {
			return err
		}
	}
	return nil
}

func (r fakeRepository) ListTimeline(_ context.Context, query domainmedia.TimelineListQuery) (domainmedia.Page, error) {
	items := make([]domainmedia.Item, 0)
	for _, item := range r.scopedItems(query.Scope) {
		if !item.SortTime.Before(query.Start) && item.SortTime.Before(query.End) {
			items = append(items, item)
		}
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].SortTime.Equal(items[j].SortTime) {
			if query.Sort == domainmedia.TimelineSortCapturedAsc {
				return items[i].ID < items[j].ID
			}
			return items[i].ID > items[j].ID
		}
		if query.Sort == domainmedia.TimelineSortCapturedAsc {
			return items[i].SortTime.Before(items[j].SortTime)
		}
		return items[i].SortTime.After(items[j].SortTime)
	})
	start := 0
	if query.After != nil {
		start = len(items)
		for index, item := range items {
			if item.ID == query.After.ID {
				start = index + 1
				break
			}
		}
	}
	return fakePage(items, start, query.Limit), nil
}

func (r fakeRepository) scopedItems(scope domainmedia.MediaScope) []domainmedia.Item {
	items := make([]domainmedia.Item, 0)
	for _, item := range r.page.Items {
		if scope.Kind != "" && item.Kind != scope.Kind {
			continue
		}
		directory := testMediaDirectory(item.MediaPath)
		switch {
		case scope.Unclassified && directory != "":
			continue
		case scope.Unclassified:
		case scope.Recursive && scope.DirectoryPath == "":
		case scope.Recursive && directory != scope.DirectoryPath && !strings.HasPrefix(directory, scope.DirectoryPath+"/"):
			continue
		case !scope.Recursive && directory != scope.DirectoryPath:
			continue
		}
		items = append(items, item)
	}
	return items
}

func testMediaDirectory(mediaPath string) string {
	directory := path.Dir(mediaPath)
	if directory == "." {
		return ""
	}
	return directory
}

func fakePage(items []domainmedia.Item, start, limit int) domainmedia.Page {
	if start > len(items) {
		start = len(items)
	}
	if limit <= 0 {
		limit = 50
	}
	end := min(start+limit, len(items))
	return domainmedia.Page{Items: items[start:end], HasMore: end < len(items)}
}

func (r fakeRepository) Upsert(context.Context, domainmedia.Item) (bool, error) {
	return false, nil
}

func (r fakeRepository) DeleteMissing(context.Context, map[string]struct{}) (int, error) {
	return 0, nil
}

func (r fakeRepository) ListPendingThumbnails(context.Context, int) ([]domainmedia.Item, error) {
	return nil, nil
}

func (r fakeRepository) UpdateThumbnail(context.Context, string, domainmedia.ThumbnailStatus, string, string) error {
	return nil
}
