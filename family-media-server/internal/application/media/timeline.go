package media

import (
	"context"
	"fmt"
	"sort"
	"time"
	_ "time/tzdata"

	domainmedia "family-media-server/internal/domain/media"
)

const defaultTimelineTimeZone = "UTC"

type resolvedTimelineQuery struct {
	location *time.Location
	timeZone string
	sort     domainmedia.TimelineSort
}

type timelineCursor struct {
	After *domainmedia.PageKey `json:"after"`
	Scope string               `json:"scope"`
}

type timelineMonthAccumulator struct {
	count  int
	covers []string
}

func (s *CatalogService) TimelineIndex(ctx context.Context, query domainmedia.TimelineQuery) (domainmedia.TimelineIndex, error) {
	resolved, err := resolveTimelineQuery(query)
	if err != nil {
		return domainmedia.TimelineIndex{}, err
	}
	scope, err := timelineMediaScope(query.Kind, query.ContainerID)
	if err != nil {
		return domainmedia.TimelineIndex{}, err
	}

	months := make(map[string]*timelineMonthAccumulator)
	err = s.repository.WalkTimelineMetadata(ctx, scope, func(metadata domainmedia.TimelineMetadata) error {
		key := metadata.SortTime.In(resolved.location).Format("2006-01")
		month := months[key]
		if month == nil {
			month = &timelineMonthAccumulator{}
			months[key] = month
		}
		month.count++
		if metadata.ThumbnailStatus == domainmedia.ThumbnailReady && metadata.ThumbnailPath != "" && len(month.covers) < 4 {
			month.covers = append(month.covers, s.thumbnailURL(metadata.ThumbnailPath))
		}
		return nil
	})
	if err != nil {
		return domainmedia.TimelineIndex{}, err
	}

	monthKeys := make([]string, 0, len(months))
	for key := range months {
		monthKeys = append(monthKeys, key)
	}
	sort.Strings(monthKeys)
	if resolved.sort == domainmedia.TimelineSortCapturedDesc {
		sort.Sort(sort.Reverse(sort.StringSlice(monthKeys)))
	}

	yearsByKey := make(map[string]*domainmedia.TimelineYear)
	yearOrder := make([]string, 0)
	for _, monthKey := range monthKeys {
		yearKey := monthKey[:4]
		year := yearsByKey[yearKey]
		if year == nil {
			year = &domainmedia.TimelineYear{Key: yearKey, CoverThumbnailURLs: []string{}}
			yearsByKey[yearKey] = year
			yearOrder = append(yearOrder, yearKey)
		}
		month := months[monthKey]
		year.Count += month.count
		year.Months = append(year.Months, domainmedia.TimelineMonth{
			Key: monthKey, Count: month.count, CoverThumbnailURLs: month.covers,
		})
		for _, cover := range month.covers {
			if len(year.CoverThumbnailURLs) >= 4 || containsString(year.CoverThumbnailURLs, cover) {
				continue
			}
			year.CoverThumbnailURLs = append(year.CoverThumbnailURLs, cover)
		}
	}

	years := make([]domainmedia.TimelineYear, 0, len(yearOrder))
	for _, key := range yearOrder {
		years = append(years, *yearsByKey[key])
	}
	return domainmedia.TimelineIndex{DateSemantics: "captured", TimeZone: resolved.timeZone, Years: years}, nil
}

func (s *CatalogService) TimelineBrowse(ctx context.Context, query domainmedia.TimelineBrowseQuery) (domainmedia.Page, error) {
	resolved, err := resolveTimelineQuery(query.TimelineQuery)
	if err != nil {
		return domainmedia.Page{}, err
	}
	if !validTimelineBucket(query.Bucket, resolved.location) {
		return domainmedia.Page{}, domainmedia.ErrInvalidBucket
	}
	scope, err := timelineMediaScope(query.Kind, query.ContainerID)
	if err != nil {
		return domainmedia.Page{}, err
	}
	monthStart, _ := time.ParseInLocation("2006-01", query.Bucket, resolved.location)
	monthEnd := monthStart.AddDate(0, 1, 0)
	limit := normalizeBrowseLimit(query.Limit)
	cursorScope := fmt.Sprintf("timeline:%s:%s:%s:%s:%s", query.Kind, query.ContainerID, query.Bucket, resolved.sort, resolved.timeZone)
	position, err := decodeTimelineCursor(query.Cursor, cursorScope)
	if err != nil {
		return domainmedia.Page{}, domainmedia.ErrInvalidCursor
	}
	page, err := s.repository.ListTimeline(ctx, domainmedia.TimelineListQuery{
		Scope: scope, Start: monthStart.UTC(), End: monthEnd.UTC(), Limit: limit,
		Sort: resolved.sort, After: position.After,
	})
	if err != nil {
		return domainmedia.Page{}, err
	}
	for index := range page.Items {
		date := page.Items[index].SortTime
		page.Items[index].TimelineDate = &date
	}
	s.attachURLs(page.Items)
	if page.HasMore && len(page.Items) > 0 {
		last := page.Items[len(page.Items)-1]
		page.NextCursor = encodeTimelineCursor(timelineCursor{
			After: &domainmedia.PageKey{ValueInt64: last.SortTime.UnixNano(), ID: last.ID},
			Scope: cursorScope,
		})
	}
	return page, nil
}

func timelineMediaScope(kind domainmedia.Kind, containerID string) (domainmedia.MediaScope, error) {
	containerPath, unclassified, err := decodeContainerID(containerID)
	if err != nil {
		return domainmedia.MediaScope{}, err
	}
	return domainmedia.MediaScope{
		Kind: kind, DirectoryPath: containerPath, Unclassified: unclassified, Recursive: true,
	}, nil
}

func resolveTimelineQuery(query domainmedia.TimelineQuery) (resolvedTimelineQuery, error) {
	timeZone := query.TimeZone
	if timeZone == "" {
		timeZone = defaultTimelineTimeZone
	}
	location, err := time.LoadLocation(timeZone)
	if err != nil {
		return resolvedTimelineQuery{}, domainmedia.ErrInvalidTimeZone
	}
	sortMode, err := normalizeTimelineSort(query.Sort)
	if err != nil {
		return resolvedTimelineQuery{}, err
	}
	return resolvedTimelineQuery{location: location, timeZone: timeZone, sort: sortMode}, nil
}

func validTimelineBucket(value string, location *time.Location) bool {
	if len(value) != len("2006-01") {
		return false
	}
	_, err := time.ParseInLocation("2006-01", value, location)
	return err == nil
}

func normalizeTimelineSort(value domainmedia.TimelineSort) (domainmedia.TimelineSort, error) {
	if value == "" {
		return domainmedia.TimelineSortCapturedDesc, nil
	}
	if value != domainmedia.TimelineSortCapturedDesc && value != domainmedia.TimelineSortCapturedAsc {
		return "", domainmedia.ErrInvalidSort
	}
	return value, nil
}

func containsString(values []string, candidate string) bool {
	for _, value := range values {
		if value == candidate {
			return true
		}
	}
	return false
}

func (s *CatalogService) thumbnailURL(thumbnailPath string) string {
	return s.publicBaseURL + "/media/thumbnails/" + pathEscape(thumbnailPath)
}

func encodeTimelineCursor(cursor timelineCursor) string {
	return encodeOpaqueCursor(cursor)
}

func decodeTimelineCursor(value string, scope string) (timelineCursor, error) {
	if value == "" {
		return timelineCursor{Scope: scope}, nil
	}
	var cursor timelineCursor
	if err := decodeOpaqueCursor(value, &cursor); err != nil || cursor.Scope != scope || cursor.After == nil || cursor.After.ID == "" {
		return timelineCursor{}, domainmedia.ErrInvalidCursor
	}
	return cursor, nil
}
