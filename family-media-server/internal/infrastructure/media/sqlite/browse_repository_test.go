package sqlite

import (
	"context"
	"testing"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

func TestDirectoryQueriesUsePersistedPathsAndNaturalKeysetPagination(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	base := time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC)
	items := []domainmedia.Item{
		item("root", domainmedia.KindPhoto, "root.jpg", base),
		item("two", domainmedia.KindVideo, "幼儿园/第2集.mp4", base.Add(time.Hour)),
		item("ten", domainmedia.KindVideo, "幼儿园/第10集.mp4", base.Add(2*time.Hour)),
		item("nested", domainmedia.KindPhoto, "幼儿园/小班/照片.jpg", base.Add(3*time.Hour)),
	}
	for _, value := range items {
		if _, err := repo.Upsert(ctx, value); err != nil {
			t.Fatal(err)
		}
	}

	paths, err := repo.ListDirectoryPaths(ctx, domainmedia.MediaScope{Recursive: true})
	if err != nil {
		t.Fatal(err)
	}
	wantPaths := []string{"", "幼儿园", "幼儿园/小班"}
	if len(paths) != len(wantPaths) {
		t.Fatalf("paths = %#v", paths)
	}
	for index := range wantPaths {
		if paths[index] != wantPaths[index] {
			t.Fatalf("paths = %#v, want %#v", paths, wantPaths)
		}
	}

	query := domainmedia.DirectListQuery{
		Scope: domainmedia.MediaScope{Kind: domainmedia.KindVideo, DirectoryPath: "幼儿园"},
		Sort:  domainmedia.SortNameAsc,
		Limit: 1,
	}
	first, err := repo.ListDirect(ctx, query)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 1 || first.Items[0].ID != "two" || !first.HasMore {
		t.Fatalf("first = %#v", first)
	}
	query.After = &domainmedia.PageKey{ValueText: first.Items[0].Name, ID: first.Items[0].ID}
	second, err := repo.ListDirect(ctx, query)
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.Items[0].ID != "ten" || second.HasMore {
		t.Fatalf("second = %#v", second)
	}
}

func TestTimelineQueriesFilterScopeTimeRangeAndUseKeyset(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	july := time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC)
	items := []domainmedia.Item{
		item("july-1", domainmedia.KindPhoto, "家庭/july-1.jpg", july.Add(time.Hour)),
		item("july-2", domainmedia.KindPhoto, "家庭/孩子/july-2.jpg", july.Add(2*time.Hour)),
		item("july-3", domainmedia.KindPhoto, "其他/july-3.jpg", july.Add(3*time.Hour)),
		item("august", domainmedia.KindPhoto, "家庭/august.jpg", july.AddDate(0, 1, 0)),
	}
	for _, value := range items {
		if _, err := repo.Upsert(ctx, value); err != nil {
			t.Fatal(err)
		}
	}
	scope := domainmedia.MediaScope{Kind: domainmedia.KindPhoto, DirectoryPath: "家庭", Recursive: true}
	metadataCount := 0
	if err := repo.WalkTimelineMetadata(ctx, scope, func(domainmedia.TimelineMetadata) error {
		metadataCount++
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if metadataCount != 3 {
		t.Fatalf("metadata count = %d, want 3", metadataCount)
	}

	query := domainmedia.TimelineListQuery{
		Scope: scope, Start: july, End: july.AddDate(0, 1, 0),
		Sort: domainmedia.TimelineSortCapturedDesc, Limit: 1,
	}
	first, err := repo.ListTimeline(ctx, query)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 1 || first.Items[0].ID != "july-2" || !first.HasMore {
		t.Fatalf("first = %#v", first)
	}
	query.After = &domainmedia.PageKey{ValueInt64: first.Items[0].SortTime.UnixNano(), ID: first.Items[0].ID}
	second, err := repo.ListTimeline(ctx, query)
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 1 || second.Items[0].ID != "july-1" || second.HasMore {
		t.Fatalf("second = %#v", second)
	}
}

func TestRecursiveScopeEscapesLikeWildcards(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	stamp := time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC)
	for _, value := range []domainmedia.Item{
		item("wanted", domainmedia.KindPhoto, "家_庭/100%/wanted.jpg", stamp),
		item("underscore", domainmedia.KindPhoto, "家庭/100%/wrong.jpg", stamp),
		item("percent", domainmedia.KindPhoto, "家_庭/1000/wrong.jpg", stamp),
	} {
		if _, err := repo.Upsert(ctx, value); err != nil {
			t.Fatal(err)
		}
	}
	count := 0
	err := repo.WalkTimelineMetadata(ctx, domainmedia.MediaScope{
		DirectoryPath: "家_庭/100%", Recursive: true,
	}, func(domainmedia.TimelineMetadata) error {
		count++
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("scoped count = %d, want 1", count)
	}
}

func TestDirectQueriesSupportEveryBrowseSort(t *testing.T) {
	repo := openTestRepository(t)
	ctx := context.Background()
	values := []domainmedia.Item{
		item("a", domainmedia.KindVideo, "目录/第10集.mp4", time.Unix(100, 0)),
		item("b", domainmedia.KindVideo, "目录/第2集.mp4", time.Unix(200, 0)),
		item("c", domainmedia.KindVideo, "目录/Alpha.mp4", time.Unix(300, 0)),
	}
	for _, value := range values {
		if _, err := repo.Upsert(ctx, value); err != nil {
			t.Fatal(err)
		}
	}
	setIndexedUnixNano(t, repo, "a", 300)
	setIndexedUnixNano(t, repo, "b", 100)
	setIndexedUnixNano(t, repo, "c", 200)
	tests := []struct {
		sort domainmedia.Sort
		want []string
	}{
		{domainmedia.SortCapturedDesc, []string{"c", "b", "a"}},
		{domainmedia.SortCapturedAsc, []string{"a", "b", "c"}},
		{domainmedia.SortNameAsc, []string{"c", "b", "a"}},
		{domainmedia.SortNameDesc, []string{"a", "b", "c"}},
		{domainmedia.SortIndexedDesc, []string{"a", "c", "b"}},
	}
	for _, test := range tests {
		page, err := repo.ListDirect(ctx, domainmedia.DirectListQuery{
			Scope: domainmedia.MediaScope{DirectoryPath: "目录"}, Sort: test.sort, Limit: 10,
		})
		if err != nil {
			t.Fatal(err)
		}
		if len(page.Items) != len(test.want) {
			t.Fatalf("sort %s items = %#v", test.sort, page.Items)
		}
		for index, id := range test.want {
			if page.Items[index].ID != id {
				t.Fatalf("sort %s item %d = %s, want %s", test.sort, index, page.Items[index].ID, id)
			}
		}
	}
}
