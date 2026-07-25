package indexing

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io/fs"
	"path/filepath"
	"strings"
	"time"

	domainmedia "family-media-server/internal/domain/media"
)

type Service interface {
	Scan(ctx context.Context) (ScanResult, error)
}

type Scanner struct {
	rootDir    string
	repository domainmedia.IndexRepository
	metadata   MetadataExtractor
}

type ScanResult struct {
	ScannedFiles      int
	IndexedFiles      int
	DeletedFiles      int
	MetadataExtracted int
	MetadataMissing   int
	MetadataFailed    int
	MetadataFallback  int
}

type MetadataExtractor interface {
	Extract(ctx context.Context, item domainmedia.Item, absolutePath string) (ExtractedMetadata, error)
}

type ExtractedMetadata struct {
	CapturedAt *time.Time
}

func NewScanner(rootDir string, repository domainmedia.IndexRepository) *Scanner {
	return &Scanner{
		rootDir:    rootDir,
		repository: repository,
	}
}

func NewScannerWithMetadata(rootDir string, repository domainmedia.IndexRepository, metadata MetadataExtractor) *Scanner {
	scanner := NewScanner(rootDir, repository)
	scanner.metadata = metadata
	return scanner
}

func (s *Scanner) Scan(ctx context.Context) (ScanResult, error) {
	seenIDs := make(map[string]struct{})
	var result ScanResult

	err := filepath.WalkDir(s.rootDir, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if entry.IsDir() {
			if shouldSkipDir(entry.Name()) && path != s.rootDir {
				return filepath.SkipDir
			}
			return nil
		}

		kind, ok := kindForPath(entry.Name())
		if !ok {
			return nil
		}

		info, err := entry.Info()
		if err != nil {
			return err
		}

		relative, err := filepath.Rel(s.rootDir, path)
		if err != nil {
			return err
		}
		mediaPath := filepath.ToSlash(relative)
		item := domainmedia.Item{
			ID:              stableID(kind, mediaPath),
			Kind:            kind,
			Name:            entry.Name(),
			MediaPath:       mediaPath,
			Size:            info.Size(),
			Modified:        info.ModTime().UTC(),
			SortTime:        info.ModTime().UTC(),
			ThumbnailStatus: domainmedia.ThumbnailPending,
		}
		if s.metadata != nil {
			metadata, err := s.metadata.Extract(ctx, item, path)
			switch {
			case err != nil:
				result.MetadataFailed++
				result.MetadataFallback++
			case metadata.CapturedAt != nil && !metadata.CapturedAt.IsZero():
				capturedAtUTC := metadata.CapturedAt.UTC()
				item.CapturedAt = &capturedAtUTC
				item.SortTime = capturedAtUTC
				result.MetadataExtracted++
			default:
				result.MetadataMissing++
				result.MetadataFallback++
			}
		}

		result.ScannedFiles++
		seenIDs[item.ID] = struct{}{}
		changed, err := s.repository.Upsert(ctx, item)
		if err != nil {
			return err
		}
		if changed {
			result.IndexedFiles++
		}
		return nil
	})
	if err != nil {
		return result, fmt.Errorf("scan media root %q: %w", s.rootDir, err)
	}

	deleted, err := s.repository.DeleteMissing(ctx, seenIDs)
	if err != nil {
		return result, err
	}
	result.DeletedFiles = deleted
	return result, nil
}

func kindForPath(name string) (domainmedia.Kind, bool) {
	ext := strings.ToLower(filepath.Ext(name))
	if _, ok := videoExtensions[ext]; ok {
		return domainmedia.KindVideo, true
	}
	if _, ok := photoExtensions[ext]; ok {
		return domainmedia.KindPhoto, true
	}
	return "", false
}

func shouldSkipDir(name string) bool {
	if strings.HasPrefix(name, ".") {
		return true
	}
	_, ok := skippedDirs[name]
	return ok
}

func stableID(kind domainmedia.Kind, mediaPath string) string {
	sum := sha1.Sum([]byte(string(kind) + ":" + mediaPath))
	return hex.EncodeToString(sum[:])
}

var videoExtensions = map[string]struct{}{
	".mp4":  {},
	".m4v":  {},
	".mov":  {},
	".mkv":  {},
	".avi":  {},
	".webm": {},
}

var photoExtensions = map[string]struct{}{
	".jpg":  {},
	".jpeg": {},
	".png":  {},
	".heic": {},
	".heif": {},
	".webp": {},
	".gif":  {},
}

var skippedDirs = map[string]struct{}{
	"@eaDir":                    {},
	"#recycle":                  {},
	".SynologyWorkingDirectory": {},
	".TemporaryItems":           {},
	".Trashes":                  {},
	".AppleDouble":              {},
	".DocumentRevisions-V100":   {},
	".Spotlight-V100":           {},
	".fseventsd":                {},
	"lost+found":                {},
}

func JobID(t time.Time) string {
	return "scan-" + t.Format("20060102-150405")
}
