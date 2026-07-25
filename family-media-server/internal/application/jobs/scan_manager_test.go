package jobs

import (
	"context"
	"errors"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	"family-media-server/internal/application/indexing"
	"family-media-server/internal/application/thumbnail"
)

func TestScanManagerCopiesMetadataCounters(t *testing.T) {
	manager := newTestScanManager(
		fakeIndexer{result: indexing.ScanResult{
			ScannedFiles:      3,
			IndexedFiles:      2,
			DeletedFiles:      1,
			MetadataExtracted: 1,
			MetadataMissing:   1,
			MetadataFailed:    1,
			MetadataFallback:  2,
		}},
		fakeThumbnailService{},
	)

	executeTestScan(manager)

	latest := manager.Status()
	if latest.MetadataExtracted != 1 || latest.MetadataMissing != 1 || latest.MetadataFailed != 1 || latest.MetadataFallback != 2 {
		t.Fatalf("metadata counters = %#v", latest)
	}
	if latest.Status != "completed" {
		t.Fatalf("status = %s", latest.Status)
	}
}

func TestScanManagerReportsThumbnailFailuresWithoutFailingScan(t *testing.T) {
	manager := newTestScanManager(
		fakeIndexer{result: indexing.ScanResult{ScannedFiles: 2, IndexedFiles: 2}},
		fakeThumbnailService{result: thumbnail.Result{
			Pending:   2,
			Generated: 1,
			Failed:    1,
			Failures: []thumbnail.Failure{
				{Code: "ffmpeg_thumbnail_failed"},
			},
		}},
	)

	executeTestScan(manager)

	latest := manager.Status()
	if latest.Status != "completed" {
		t.Fatalf("status = %s", latest.Status)
	}
	if latest.ThumbnailPending != 2 || latest.ThumbnailGenerated != 1 || latest.ThumbnailFailed != 1 {
		t.Fatalf("thumbnail counters = %#v", latest)
	}
	if latest.ThumbnailError != "ffmpeg_thumbnail_failed" {
		t.Fatalf("thumbnail error = %q", latest.ThumbnailError)
	}
	if latest.Error != "" {
		t.Fatalf("error = %q", latest.Error)
	}
}

func TestScanManagerFailsWhenThumbnailBatchReturnsSystemError(t *testing.T) {
	manager := newTestScanManager(
		fakeIndexer{result: indexing.ScanResult{ScannedFiles: 1, IndexedFiles: 1}},
		fakeThumbnailService{err: errors.New("list pending thumbnails: database locked")},
	)

	executeTestScan(manager)

	latest := manager.Status()
	if latest.Status != "failed" {
		t.Fatalf("status = %s", latest.Status)
	}
	if latest.Error != "thumbnail_batch_failed" {
		t.Fatalf("error = %q", latest.Error)
	}
}

func TestScanManagerUsesLifecycleContextAndWaitsForActiveScan(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	started := make(chan struct{})
	indexer := &blockingIndexer{started: started}
	manager := NewScanManager(ctx, indexer, fakeThumbnailService{}, time.Hour, 10, slog.Default())

	done := make(chan error, 1)
	go func() { done <- manager.Run(ctx) }()
	<-started
	cancel()

	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("run error = %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("scan manager did not wait for cancelled worker")
	}
	if indexer.calls.Load() != 1 {
		t.Fatalf("scan calls = %d", indexer.calls.Load())
	}
	if manager.Status().Status != ScanFailed {
		t.Fatalf("status = %s", manager.Status().Status)
	}
}

func TestConcurrentTriggersReuseTheActiveScan(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started := make(chan struct{})
	indexer := &blockingIndexer{started: started}
	manager := NewScanManager(ctx, indexer, fakeThumbnailService{}, time.Hour, 10, slog.Default())

	first := manager.Trigger()
	<-started
	second := manager.Trigger()
	if first.JobID != second.JobID {
		t.Fatalf("job IDs differ: %q != %q", first.JobID, second.JobID)
	}
	if indexer.calls.Load() != 1 {
		t.Fatalf("scan calls = %d", indexer.calls.Load())
	}
	cancel()
}

func newTestScanManager(indexer indexing.Service, thumbnails ThumbnailGenerator) *ScanManager {
	return NewScanManager(context.Background(), indexer, thumbnails, time.Hour, 10, slog.Default())
}

func executeTestScan(manager *ScanManager) {
	manager.execute(context.Background(), ScanStatus{
		JobID:     "scan-1",
		Status:    "running",
		StartedAt: time.Now().UTC(),
	})
}

type fakeIndexer struct {
	result indexing.ScanResult
	err    error
}

func (i fakeIndexer) Scan(context.Context) (indexing.ScanResult, error) {
	return i.result, i.err
}

type fakeThumbnailService struct {
	result thumbnail.Result
	err    error
}

type blockingIndexer struct {
	started chan struct{}
	calls   atomic.Int32
}

func (i *blockingIndexer) Scan(ctx context.Context) (indexing.ScanResult, error) {
	if i.calls.Add(1) == 1 {
		close(i.started)
	}
	<-ctx.Done()
	return indexing.ScanResult{}, ctx.Err()
}

func (s fakeThumbnailService) GeneratePending(context.Context, int) (thumbnail.Result, error) {
	return s.result, s.err
}
