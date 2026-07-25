package thumbnail

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"

	domainmedia "family-media-server/internal/domain/media"
)

type Generator interface {
	Generate(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string) error
}

type Option func(*options)

type options struct {
	TimeOffsetSeconds int
}

type Service struct {
	rootDir    string
	cacheDir   string
	repository domainmedia.ThumbnailRepository
	generator  Generator

	reconcileMu        sync.Mutex
	retriedOldFailures bool
}

type Result struct {
	Pending   int
	Generated int
	Failed    int
	Failures  []Failure
}

type Failure struct {
	Code string
}

func NewService(rootDir string, cacheDir string, generator Generator, repository domainmedia.ThumbnailRepository) *Service {
	return &Service{
		rootDir:    rootDir,
		cacheDir:   cacheDir,
		generator:  generator,
		repository: repository,
	}
}

func (s *Service) GeneratePending(ctx context.Context, limit int) (Result, error) {
	if err := s.reconcileMissingThumbnails(ctx); err != nil {
		return Result{}, err
	}

	var result Result
	for {
		if err := ctx.Err(); err != nil {
			return result, err
		}

		items, err := s.repository.ListPendingThumbnails(ctx, limit)
		if err != nil {
			return result, err
		}
		if len(items) == 0 {
			return result, nil
		}

		result.Pending += len(items)
		for _, item := range items {
			thumbnailPath, err := s.generate(ctx, item)
			if err != nil {
				if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
					return result, err
				}
				result.recordFailure(err)
				if updateErr := s.markFailed(ctx, item, err); updateErr != nil {
					return result, updateErr
				}
				continue
			}
			result.Generated++
			if err := s.repository.UpdateThumbnail(ctx, item.ID, domainmedia.ThumbnailReady, thumbnailPath, ""); err != nil {
				return result, err
			}
		}
		if len(items) < limit {
			return result, nil
		}
	}
}

func (s *Service) reconcileMissingThumbnails(ctx context.Context) error {
	items, err := s.repository.ListReadyThumbnails(ctx)
	if err != nil {
		return err
	}
	for _, item := range items {
		if err := ctx.Err(); err != nil {
			return err
		}
		if item.ThumbnailPath != "" {
			path := filepath.Join(s.cacheDir, filepath.FromSlash(item.ThumbnailPath))
			if _, err := os.Stat(path); err == nil {
				continue
			} else if !os.IsNotExist(err) {
				return err
			}
		}
		if err := s.repository.UpdateThumbnail(ctx, item.ID, domainmedia.ThumbnailPending, "", ""); err != nil {
			return err
		}
	}
	return s.retryHistoricalFailures(ctx)
}

// retryHistoricalFailures gives thumbnails produced by an older server image
// one chance to benefit from newly added decoders. The in-memory guard avoids
// repeatedly processing permanently corrupt files on every scan.
func (s *Service) retryHistoricalFailures(ctx context.Context) error {
	s.reconcileMu.Lock()
	defer s.reconcileMu.Unlock()
	if s.retriedOldFailures {
		return nil
	}

	items, err := s.repository.ListFailedThumbnails(ctx)
	if err != nil {
		return err
	}
	for _, item := range items {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := s.repository.UpdateThumbnail(ctx, item.ID, domainmedia.ThumbnailPending, "", ""); err != nil {
			return err
		}
	}
	s.retriedOldFailures = true
	return nil
}

func (r *Result) recordFailure(err error) {
	r.Failed++
	r.Failures = append(r.Failures, Failure{Code: generationErrorCode(err)})
}

func (s *Service) markFailed(ctx context.Context, item domainmedia.Item, err error) error {
	return s.repository.UpdateThumbnail(ctx, item.ID, domainmedia.ThumbnailFailed, "", generationErrorCode(err))
}

func (s *Service) Regenerate(ctx context.Context, id string, opts ...Option) (domainmedia.Item, error) {
	item, err := s.repository.GetByID(ctx, id)
	if err != nil {
		return domainmedia.Item{}, err
	}

	if item.ThumbnailPath != "" {
		_ = os.Remove(filepath.Join(s.cacheDir, filepath.FromSlash(item.ThumbnailPath)))
	}

	thumbnailPath, err := s.generate(ctx, item, opts...)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return domainmedia.Item{}, err
		}
		_ = s.markFailed(ctx, item, err)
		item.ThumbnailStatus = domainmedia.ThumbnailFailed
		item.ThumbnailPath = ""
		item.LastError = generationErrorCode(err)
		return item, nil
	}

	if err := s.repository.UpdateThumbnail(ctx, item.ID, domainmedia.ThumbnailReady, thumbnailPath, ""); err != nil {
		return domainmedia.Item{}, err
	}
	item.ThumbnailStatus = domainmedia.ThumbnailReady
	item.ThumbnailPath = thumbnailPath
	item.LastError = ""
	return item, nil
}

func generationErrorCode(err error) string {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return "thumbnail_cancelled"
	}
	var coded interface{ Code() string }
	if errors.As(err, &coded) && coded.Code() != "" {
		return coded.Code()
	}
	return "thumbnail_generation_failed"
}

func WithTimeOffsetSeconds(seconds int) Option {
	return func(opts *options) {
		opts.TimeOffsetSeconds = seconds
	}
}

func (s *Service) generate(ctx context.Context, item domainmedia.Item, opts ...Option) (string, error) {
	options := options{}
	for _, opt := range opts {
		opt(&options)
	}

	relative := filepath.Join(item.ID[0:2], item.ID[2:4], item.ID+".jpg")
	outputPath := filepath.Join(s.cacheDir, relative)
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return "", err
	}

	inputPath := filepath.Join(s.rootDir, filepath.FromSlash(item.MediaPath))
	if timed, ok := s.generator.(TimedGenerator); ok && options.TimeOffsetSeconds > 0 {
		return relative, timed.GenerateAt(ctx, item, inputPath, outputPath, options.TimeOffsetSeconds)
	}
	return relative, s.generator.Generate(ctx, item, inputPath, outputPath)
}

type TimedGenerator interface {
	GenerateAt(ctx context.Context, item domainmedia.Item, inputPath string, outputPath string, timeOffsetSeconds int) error
}
