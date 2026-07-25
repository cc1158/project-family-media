package media

import (
	"context"
	"errors"
	"testing"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

func TestBrowsePreservesNestedFoldersAndCollectsRootFiles(t *testing.T) {
	service := browseTestService()

	root, err := service.Browse(context.Background(), "", "", 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, root.Items, []string{"出生", "幼儿园", "未分类"})
	for _, item := range root.Items {
		if !item.IsContainer || item.ContainerID == "" {
			t.Fatalf("root item is not a navigable folder: %#v", item)
		}
	}

	kindergarten := root.Items[1]
	children, err := service.Browse(context.Background(), "", kindergarten.ContainerID, 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, children.Items, []string{"小班", "photo.jpg", "day.mp4"})
	if !children.Items[0].IsContainer || children.Items[1].IsContainer {
		t.Fatalf("folders should precede direct media: %#v", children.Items)
	}

	unclassified := root.Items[2]
	loose, err := service.Browse(context.Background(), "", unclassified.ContainerID, 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, loose.Items, []string{"loose.mp4"})
}

func TestBrowseFiltersFolderTreeByMediaKind(t *testing.T) {
	service := browseTestService()

	videos, err := service.Browse(context.Background(), domainmedia.KindVideo, "", 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, videos.Items, []string{"幼儿园", "未分类"})

	children, err := service.Browse(
		context.Background(),
		domainmedia.KindVideo,
		videos.Items[0].ContainerID,
		50,
		"",
		"",
	)
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, children.Items, []string{"小班", "day.mp4"})

	photos, err := service.Browse(context.Background(), domainmedia.KindPhoto, "", 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, photos.Items, []string{"出生", "幼儿园"})
}

func TestBrowseCursorContinuesFromFoldersIntoDirectMedia(t *testing.T) {
	service := browseTestService()
	root, err := service.Browse(context.Background(), "", "", 50, "", "")
	if err != nil {
		t.Fatal(err)
	}
	containerID := root.Items[1].ContainerID
	first, err := service.Browse(context.Background(), "", containerID, 2, "", domainmedia.SortCapturedDesc)
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, first.Items, []string{"小班", "photo.jpg"})
	if !first.HasMore || first.NextCursor == "" {
		t.Fatalf("first page = %#v", first)
	}
	second, err := service.Browse(context.Background(), "", containerID, 2, first.NextCursor, domainmedia.SortCapturedDesc)
	if err != nil {
		t.Fatal(err)
	}
	assertBrowseNames(t, second.Items, []string{"day.mp4"})
	if second.HasMore {
		t.Fatalf("second page = %#v", second)
	}
}

func TestBrowseCursorIsScopedAndInvalidContainersAreRejected(t *testing.T) {
	service := browseTestService()
	first, err := service.Browse(context.Background(), "", "", 1, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if !first.HasMore || first.NextCursor == "" || len(first.Items) != 1 {
		t.Fatalf("first page = %#v", first)
	}
	second, err := service.Browse(context.Background(), "", "", 1, first.NextCursor, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.Items[0].Name == first.Items[0].Name {
		t.Fatalf("second page = %#v", second)
	}
	if _, err := service.Browse(context.Background(), domainmedia.KindVideo, "", 1, first.NextCursor, ""); !errors.Is(err, domainmedia.ErrInvalidCursor) {
		t.Fatalf("cross-filter cursor error = %v", err)
	}
	if _, err := service.Browse(context.Background(), "", "", 1, first.NextCursor, domainmedia.SortNameAsc); !errors.Is(err, domainmedia.ErrInvalidCursor) {
		t.Fatalf("cross-sort cursor error = %v", err)
	}
	if _, err := service.Browse(context.Background(), "", "../../etc", 50, "", ""); !errors.Is(err, domainmedia.ErrInvalidContainer) {
		t.Fatalf("invalid container error = %v", err)
	}
	if _, err := service.Browse(context.Background(), "", "", 50, "", "size_desc"); !errors.Is(err, domainmedia.ErrInvalidSort) {
		t.Fatalf("invalid sort error = %v", err)
	}
	unknownCursor := encodeOpaqueCursor(map[string]any{"offset": 1, "scope": browseScope("", "", domainmedia.SortCapturedDesc)})
	if _, err := service.Browse(context.Background(), "", "", 1, unknownCursor, ""); !errors.Is(err, domainmedia.ErrInvalidCursor) {
		t.Fatalf("unknown cursor shape error = %v", err)
	}
}

func TestSortBrowseEntriesSupportsMediaSortModes(t *testing.T) {
	base := time.Date(2026, 7, 20, 8, 0, 0, 0, time.UTC)
	items := []domainmedia.Item{
		{ID: "2", Name: "第10集.mp4", SortTime: base.Add(time.Hour), IndexedAt: base.Add(3 * time.Hour)},
		{ID: "1", Name: "第2集.mp4", SortTime: base, IndexedAt: base.Add(4 * time.Hour)},
		{ID: "3", Name: "Alpha.mp4", SortTime: base.Add(2 * time.Hour), IndexedAt: base.Add(time.Hour)},
	}
	tests := []struct {
		name string
		sort domainmedia.Sort
		want []string
	}{
		{"captured newest", domainmedia.SortCapturedDesc, []string{"Alpha.mp4", "第10集.mp4", "第2集.mp4"}},
		{"captured oldest", domainmedia.SortCapturedAsc, []string{"第2集.mp4", "第10集.mp4", "Alpha.mp4"}},
		{"name ascending", domainmedia.SortNameAsc, []string{"Alpha.mp4", "第2集.mp4", "第10集.mp4"}},
		{"name descending", domainmedia.SortNameDesc, []string{"第10集.mp4", "第2集.mp4", "Alpha.mp4"}},
		{"indexed newest", domainmedia.SortIndexedDesc, []string{"第2集.mp4", "第10集.mp4", "Alpha.mp4"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			actual := append([]domainmedia.Item(nil), items...)
			sortBrowseEntries(actual, test.sort)
			assertBrowseNames(t, actual, test.want)
		})
	}
}

func TestSortBrowseEntriesKeepsNaturallySortedFoldersFirstAndUnclassifiedLast(t *testing.T) {
	items := []domainmedia.Item{
		{ID: "media", Name: "latest.mp4", SortTime: time.Now()},
		{ID: "folder-10", Name: "第10集", IsContainer: true, ContainerID: "folder-10"},
		{ID: "unclassified", Name: "未分类", IsContainer: true, ContainerID: unclassifiedContainerID},
		{ID: "folder-2", Name: "第2集", IsContainer: true, ContainerID: "folder-2"},
	}

	sortBrowseEntries(items, domainmedia.SortCapturedDesc)

	assertBrowseNames(t, items, []string{"第2集", "第10集", "未分类", "latest.mp4"})
}

func TestSortBrowseEntriesUsesStableIDTieBreaker(t *testing.T) {
	stamp := time.Date(2026, 7, 20, 8, 0, 0, 0, time.UTC)
	items := []domainmedia.Item{
		{ID: "a", Name: "same.mp4", SortTime: stamp},
		{ID: "b", Name: "same.mp4", SortTime: stamp},
	}

	sortBrowseEntries(items, domainmedia.SortCapturedDesc)
	if items[0].ID != "b" {
		t.Fatalf("captured tie order = %#v", items)
	}
	sortBrowseEntries(items, domainmedia.SortNameAsc)
	if items[0].ID != "a" {
		t.Fatalf("name tie order = %#v", items)
	}
}

func browseTestService() *CatalogService {
	base := time.Date(2026, 7, 19, 8, 0, 0, 0, time.UTC)
	item := func(id string, name string, mediaPath string, kind domainmedia.Kind, minutes int) domainmedia.Item {
		stamp := base.Add(time.Duration(minutes) * time.Minute)
		return domainmedia.Item{
			ID:              id,
			Name:            name,
			MediaPath:       mediaPath,
			Kind:            kind,
			Modified:        stamp,
			SortTime:        stamp,
			IndexedAt:       stamp,
			ThumbnailStatus: domainmedia.ThumbnailReady,
			ThumbnailPath:   "ab/cd/" + id + ".jpg",
		}
	}
	return NewCatalogService(fakeRepository{page: domainmedia.Page{Items: []domainmedia.Item{
		item("loose", "loose.mp4", "loose.mp4", domainmedia.KindVideo, 1),
		item("day", "day.mp4", "幼儿园/day.mp4", domainmedia.KindVideo, 2),
		item("photo", "photo.jpg", "幼儿园/photo.jpg", domainmedia.KindPhoto, 3),
		item("class", "class.mov", "幼儿园/小班/class.mov", domainmedia.KindVideo, 4),
		item("birth", "baby.heic", "出生/baby.heic", domainmedia.KindPhoto, 5),
	}}}, "http://localhost:8080")
}

func assertBrowseNames(t *testing.T, items []domainmedia.Item, want []string) {
	t.Helper()
	if len(items) != len(want) {
		t.Fatalf("names length = %d, want %d; items = %#v", len(items), len(want), items)
	}
	for index, name := range want {
		if items[index].Name != name {
			t.Fatalf("item %d name = %q, want %q", index, items[index].Name, name)
		}
	}
}
