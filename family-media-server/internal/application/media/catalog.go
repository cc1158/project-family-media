package media

import (
	"context"
	"net/url"

	domainmedia "family-media-server/internal/domain/media"
)

type CatalogService struct {
	repository    domainmedia.CatalogRepository
	publicBaseURL string
}

func NewCatalogService(repository domainmedia.CatalogRepository, publicBaseURL string) *CatalogService {
	return &CatalogService{
		repository:    repository,
		publicBaseURL: publicBaseURL,
	}
}

func (s *CatalogService) Videos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	query.Kind = domainmedia.KindVideo
	return s.list(ctx, query)
}

func (s *CatalogService) Photos(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	query.Kind = domainmedia.KindPhoto
	return s.list(ctx, query)
}

func (s *CatalogService) Media(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	return s.list(ctx, query)
}

func (s *CatalogService) list(ctx context.Context, query domainmedia.ListQuery) (domainmedia.Page, error) {
	page, err := s.repository.List(ctx, query)
	if err != nil {
		return domainmedia.Page{}, err
	}
	s.attachURLs(page.Items)
	return page, nil
}

func (s *CatalogService) attachURLs(items []domainmedia.Item) {
	for i := range items {
		if items[i].IsContainer {
			items[i].URL = s.publicBaseURL
		} else {
			items[i].URL = s.publicBaseURL + mediaURLPrefix(items[i].Kind) + pathEscape(items[i].MediaPath)
		}
		if items[i].ThumbnailPath != "" {
			items[i].ThumbnailURL = s.publicBaseURL + "/media/thumbnails/" + pathEscape(items[i].ThumbnailPath)
		}
	}
}

func mediaURLPrefix(kind domainmedia.Kind) string {
	return "/media/original/"
}

func pathEscape(path string) string {
	escaped := (&url.URL{Path: path}).EscapedPath()
	if len(escaped) > 0 && escaped[0] == '/' {
		return escaped[1:]
	}
	return escaped
}
