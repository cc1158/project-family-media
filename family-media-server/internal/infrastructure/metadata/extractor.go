package metadata

import (
	"context"
	"time"

	"family-media-server/internal/application/indexing"
	domainmedia "family-media-server/internal/domain/media"
)

type Extractor struct{}

func NewExtractor() *Extractor {
	return &Extractor{}
}

func (e *Extractor) Extract(ctx context.Context, item domainmedia.Item, absolutePath string) (indexing.ExtractedMetadata, error) {
	var capturedAt *time.Time
	var err error
	switch item.Kind {
	case domainmedia.KindPhoto:
		capturedAt, err = photoCapturedAt(absolutePath)
	case domainmedia.KindVideo:
		capturedAt, err = videoCapturedAt(ctx, absolutePath)
	default:
		return indexing.ExtractedMetadata{}, nil
	}
	if err != nil {
		return indexing.ExtractedMetadata{}, err
	}
	return indexing.ExtractedMetadata{CapturedAt: capturedAt}, nil
}
