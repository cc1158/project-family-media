package media

import (
	"context"
	"errors"
	"testing"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

func TestTimelineIndexGroupsRecursivelyAndUsesRequestedTimeZone(t *testing.T) {
	service := browseTestService()
	index, err := service.TimelineIndex(context.Background(), domainmedia.TimelineQuery{
		TimeZone: "Asia/Shanghai", Sort: domainmedia.TimelineSortCapturedDesc,
	})
	if err != nil {
		t.Fatal(err)
	}
	if index.TimeZone != "Asia/Shanghai" || len(index.Years) != 1 || index.Years[0].Count != 5 {
		t.Fatalf("index = %#v", index)
	}
	if len(index.Years[0].Months) != 1 || index.Years[0].Months[0].Key != "2026-07" {
		t.Fatalf("months = %#v", index.Years[0].Months)
	}
	if got := len(index.Years[0].CoverThumbnailURLs); got != 4 {
		t.Fatalf("covers = %d, want 4", got)
	}
}

func TestTimelineScopesFolderAndUnclassifiedMedia(t *testing.T) {
	service := browseTestService()
	root, err := service.Browse(context.Background(), "", "", 50, "", "")
	if err != nil {
		t.Fatal(err)
	}

	folder := root.Items[1]
	index, err := service.TimelineIndex(context.Background(), domainmedia.TimelineQuery{ContainerID: folder.ContainerID, TimeZone: "UTC"})
	if err != nil {
		t.Fatal(err)
	}
	if len(index.Years) != 1 || index.Years[0].Count != 3 {
		t.Fatalf("folder index = %#v", index)
	}

	unclassified := root.Items[2]
	index, err = service.TimelineIndex(context.Background(), domainmedia.TimelineQuery{ContainerID: unclassified.ContainerID, TimeZone: "UTC"})
	if err != nil {
		t.Fatal(err)
	}
	if len(index.Years) != 1 || index.Years[0].Count != 1 {
		t.Fatalf("unclassified index = %#v", index)
	}
}

func TestTimelineBrowsePaginatesAndScopesCursor(t *testing.T) {
	service := browseTestService()
	query := domainmedia.TimelineBrowseQuery{
		TimelineQuery: domainmedia.TimelineQuery{TimeZone: "UTC", Sort: domainmedia.TimelineSortCapturedDesc},
		Bucket:        "2026-07", Limit: 2,
	}
	first, err := service.TimelineBrowse(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 2 || !first.HasMore || first.Items[0].TimelineDate == nil {
		t.Fatalf("first page = %#v", first)
	}
	query.Cursor = first.NextCursor
	second, err := service.TimelineBrowse(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 2 || second.Items[0].ID == first.Items[1].ID {
		t.Fatalf("second page = %#v", second)
	}
	query.Cursor = first.NextCursor
	query.Sort = domainmedia.TimelineSortCapturedAsc
	if _, err := service.TimelineBrowse(context.Background(), query); !errors.Is(err, domainmedia.ErrInvalidCursor) {
		t.Fatalf("cross-sort cursor error = %v", err)
	}
}

func TestTimelineRejectsInvalidInputs(t *testing.T) {
	service := browseTestService()
	if _, err := service.TimelineIndex(context.Background(), domainmedia.TimelineQuery{TimeZone: "Mars/Home"}); !errors.Is(err, domainmedia.ErrInvalidTimeZone) {
		t.Fatalf("time zone error = %v", err)
	}
	if _, err := service.TimelineBrowse(context.Background(), domainmedia.TimelineBrowseQuery{TimelineQuery: domainmedia.TimelineQuery{TimeZone: "UTC"}, Bucket: "2026-13"}); !errors.Is(err, domainmedia.ErrInvalidBucket) {
		t.Fatalf("bucket error = %v", err)
	}
}

func TestTimelineUsesRequestedTimeZoneAtMonthBoundary(t *testing.T) {
	beforeBoundary := time.Date(2026, 6, 30, 15, 30, 0, 0, time.UTC)
	afterBoundary := time.Date(2026, 6, 30, 16, 30, 0, 0, time.UTC)
	service := NewCatalogService(fakeRepository{page: domainmedia.Page{Items: []domainmedia.Item{
		{ID: "june", Kind: domainmedia.KindPhoto, MediaPath: "june.jpg", SortTime: beforeBoundary},
		{ID: "july", Kind: domainmedia.KindPhoto, MediaPath: "july.jpg", SortTime: afterBoundary},
	}}}, "http://localhost:8080")

	index, err := service.TimelineIndex(context.Background(), domainmedia.TimelineQuery{
		TimeZone: "Asia/Shanghai",
		Sort:     domainmedia.TimelineSortCapturedAsc,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(index.Years) != 1 || len(index.Years[0].Months) != 2 {
		t.Fatalf("index = %#v", index)
	}
	if index.Years[0].Months[0].Key != "2026-06" || index.Years[0].Months[1].Key != "2026-07" {
		t.Fatalf("months = %#v", index.Years[0].Months)
	}
}
