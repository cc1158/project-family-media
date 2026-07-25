package media

import (
	"sort"

	domainmedia "family-media-server/internal/domain/media"
)

func sortBrowseEntries(items []domainmedia.Item, sortMode domainmedia.Sort) {
	sort.SliceStable(items, func(i int, j int) bool {
		left, right := items[i], items[j]
		if left.IsContainer != right.IsContainer {
			return left.IsContainer
		}
		if left.IsContainer {
			if left.ContainerID == unclassifiedContainerID {
				return false
			}
			if right.ContainerID == unclassifiedContainerID {
				return true
			}
			return domainmedia.NaturalCompare(left.Name, right.Name) < 0
		}
		switch sortMode {
		case domainmedia.SortCapturedAsc:
			if !left.SortTime.Equal(right.SortTime) {
				return left.SortTime.Before(right.SortTime)
			}
			return left.ID < right.ID
		case domainmedia.SortNameAsc:
			if comparison := domainmedia.NaturalCompare(left.Name, right.Name); comparison != 0 {
				return comparison < 0
			}
			return left.ID < right.ID
		case domainmedia.SortNameDesc:
			if comparison := domainmedia.NaturalCompare(left.Name, right.Name); comparison != 0 {
				return comparison > 0
			}
			return left.ID > right.ID
		case domainmedia.SortIndexedDesc:
			if !left.IndexedAt.Equal(right.IndexedAt) {
				return left.IndexedAt.After(right.IndexedAt)
			}
			return left.ID > right.ID
		default:
			if !left.SortTime.Equal(right.SortTime) {
				return left.SortTime.After(right.SortTime)
			}
			return left.ID > right.ID
		}
	})
}

func normalizeBrowseSort(value domainmedia.Sort) (domainmedia.Sort, error) {
	if value == "" {
		return domainmedia.SortCapturedDesc, nil
	}
	switch value {
	case domainmedia.SortCapturedDesc,
		domainmedia.SortCapturedAsc,
		domainmedia.SortNameAsc,
		domainmedia.SortNameDesc,
		domainmedia.SortIndexedDesc:
		return value, nil
	default:
		return "", domainmedia.ErrInvalidSort
	}
}

func pageKey(item domainmedia.Item, sortMode domainmedia.Sort) domainmedia.PageKey {
	key := domainmedia.PageKey{ID: item.ID}
	switch sortMode {
	case domainmedia.SortNameAsc, domainmedia.SortNameDesc:
		key.ValueText = item.Name
	case domainmedia.SortIndexedDesc:
		key.ValueInt64 = item.IndexedAt.UnixNano()
	default:
		key.ValueInt64 = item.SortTime.UnixNano()
	}
	return key
}
