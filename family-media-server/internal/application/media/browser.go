package media

import (
	"context"
	"path"
	"strings"

	domainmedia "family-media-server/internal/domain/media"
)

func (s *CatalogService) Browse(
	ctx context.Context,
	kind domainmedia.Kind,
	containerID string,
	limit int,
	cursor string,
	sortMode domainmedia.Sort,
) (domainmedia.Page, error) {
	sortMode, err := normalizeBrowseSort(sortMode)
	if err != nil {
		return domainmedia.Page{}, err
	}
	containerPath, isUnclassified, err := decodeContainerID(containerID)
	if err != nil {
		return domainmedia.Page{}, err
	}

	scope := domainmedia.MediaScope{
		Kind: kind, DirectoryPath: containerPath, Unclassified: isUnclassified, Recursive: true,
	}
	directoryPaths, err := s.repository.ListDirectoryPaths(ctx, scope)
	if err != nil {
		return domainmedia.Page{}, err
	}
	folders, err := s.browseFolders(ctx, kind, containerPath, isUnclassified, directoryPaths)
	if err != nil {
		return domainmedia.Page{}, err
	}

	limit = normalizeBrowseLimit(limit)
	cursorScope := browseScope(kind, containerID, sortMode)
	position, err := decodeBrowseCursor(cursor, cursorScope)
	if err != nil {
		return domainmedia.Page{}, domainmedia.ErrInvalidCursor
	}
	if position.FolderOffset < 0 || position.FolderOffset > len(folders) {
		return domainmedia.Page{}, domainmedia.ErrInvalidCursor
	}
	if position.Media != nil && (position.Media.ID == "" || position.FolderOffset != len(folders)) {
		return domainmedia.Page{}, domainmedia.ErrInvalidCursor
	}

	pageItems := make([]domainmedia.Item, 0, limit)
	folderEnd := min(position.FolderOffset+limit, len(folders))
	pageItems = append(pageItems, folders[position.FolderOffset:folderEnd]...)
	remaining := limit - len(pageItems)
	directPage := domainmedia.Page{}
	canIncludeDirect := isUnclassified || containerPath != ""
	if folderEnd == len(folders) && canIncludeDirect {
		directLimit := remaining
		if directLimit == 0 {
			directLimit = 1
		}
		directPage, err = s.repository.ListDirect(ctx, domainmedia.DirectListQuery{
			Scope: domainmedia.MediaScope{
				Kind: kind, DirectoryPath: containerPath, Unclassified: isUnclassified,
			},
			Limit: directLimit, Sort: sortMode, After: position.Media,
		})
		if err != nil {
			return domainmedia.Page{}, err
		}
		if remaining > 0 {
			pageItems = append(pageItems, directPage.Items...)
		}
	}
	s.attachURLs(pageItems)

	hasMoreFolders := folderEnd < len(folders)
	hasUnreturnedDirect := remaining == 0 && len(directPage.Items) > 0
	hasMore := hasMoreFolders || hasUnreturnedDirect || directPage.HasMore
	var nextCursor string
	if hasMore {
		nextPosition := browseCursor{Scope: cursorScope, FolderOffset: folderEnd}
		if remaining > 0 && len(directPage.Items) > 0 {
			key := pageKey(directPage.Items[len(directPage.Items)-1], sortMode)
			nextPosition.Media = &key
		}
		nextCursor = encodeBrowseCursor(nextPosition)
	}
	return domainmedia.Page{
		Items:      pageItems,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, nil
}

func (s *CatalogService) browseFolders(
	ctx context.Context,
	kind domainmedia.Kind,
	containerPath string,
	isUnclassified bool,
	directoryPaths []string,
) ([]domainmedia.Item, error) {
	if isUnclassified {
		return nil, nil
	}
	children := make(map[string]struct{})
	for _, directory := range directoryPaths {
		if directory == "" || directory == containerPath {
			continue
		}
		remainder := directory
		if containerPath != "" {
			prefix := containerPath + "/"
			if !strings.HasPrefix(directory, prefix) {
				continue
			}
			remainder = strings.TrimPrefix(directory, prefix)
		}
		childName := strings.SplitN(remainder, "/", 2)[0]
		children[path.Join(containerPath, childName)] = struct{}{}
	}

	folders := make([]domainmedia.Item, 0, len(children)+1)
	for childPath := range children {
		folder, ok, err := s.folderItem(ctx, kind, childPath, encodeFolderContainerID(childPath), path.Base(childPath))
		if err != nil {
			return nil, err
		}
		if ok {
			folders = append(folders, folder)
		}
	}
	if containerPath == "" {
		folder, ok, err := s.folderItem(ctx, kind, "", unclassifiedContainerID, unclassifiedContainerName)
		if err != nil {
			return nil, err
		}
		if ok {
			folders = append(folders, folder)
		}
	}
	sortBrowseEntries(folders, domainmedia.SortNameAsc)
	return folders, nil
}

func (s *CatalogService) folderItem(
	ctx context.Context,
	kind domainmedia.Kind,
	directoryPath string,
	containerID string,
	name string,
) (domainmedia.Item, bool, error) {
	scope := domainmedia.MediaScope{Kind: kind, DirectoryPath: directoryPath, Recursive: true}
	if containerID == unclassifiedContainerID {
		scope.Unclassified = true
	}
	summary, ok, err := s.repository.SummarizeScope(ctx, scope)
	if err != nil || !ok {
		return domainmedia.Item{}, false, err
	}
	folderKind := kind
	if folderKind == "" {
		folderKind = summary.Newest.Kind
	}
	item := domainmedia.Item{
		ID:              containerID,
		Name:            name,
		Kind:            folderKind,
		Modified:        summary.Newest.Modified,
		MediaPath:       directoryPath,
		ThumbnailStatus: domainmedia.ThumbnailReady,
		ContainerID:     containerID,
		IsContainer:     true,
		SortTime:        summary.Newest.SortTime,
	}
	if summary.Cover != nil {
		item.ThumbnailPath = summary.Cover.ThumbnailPath
	}
	return item, true, nil
}
