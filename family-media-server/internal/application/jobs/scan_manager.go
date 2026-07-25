package jobs

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"family-media-server/internal/application/indexing"
	"family-media-server/internal/application/thumbnail"
)

type ThumbnailGenerator interface {
	GeneratePending(ctx context.Context, limit int) (thumbnail.Result, error)
}

var ErrMaintenanceBusy = errors.New("media maintenance is busy")

type ScanManager struct {
	lifecycleCtx   context.Context
	indexer        indexing.Service
	thumbnails     ThumbnailGenerator
	interval       time.Duration
	thumbnailBatch int
	logger         *slog.Logger
	mu             sync.Mutex
	running        bool
	maintenance    bool
	accepting      bool
	lastStatus     ScanStatus
	workers        sync.WaitGroup
}

func NewScanManager(lifecycleCtx context.Context, indexer indexing.Service, thumbnails ThumbnailGenerator, interval time.Duration, thumbnailBatch int, logger *slog.Logger) *ScanManager {
	return &ScanManager{
		lifecycleCtx:   lifecycleCtx,
		indexer:        indexer,
		thumbnails:     thumbnails,
		interval:       interval,
		thumbnailBatch: thumbnailBatch,
		logger:         logger,
		accepting:      true,
		lastStatus: ScanStatus{
			Status: ScanIdle,
		},
	}
}

func (m *ScanManager) Name() string {
	return "media-scan"
}

func (m *ScanManager) Run(ctx context.Context) error {
	m.Trigger()
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			m.mu.Lock()
			m.accepting = false
			m.mu.Unlock()
			m.workers.Wait()
			return ctx.Err()
		case <-ticker.C:
			m.Trigger()
		}
	}
}

func (m *ScanManager) Trigger() ScanStatus {
	m.mu.Lock()
	if !m.accepting || m.lifecycleCtx.Err() != nil || m.running || m.maintenance {
		status := m.lastStatus
		m.mu.Unlock()
		return status
	}

	now := time.Now().UTC()
	status := ScanStatus{
		JobID:     indexing.JobID(now),
		Status:    ScanRunning,
		StartedAt: now,
	}
	m.running = true
	m.lastStatus = status
	m.workers.Add(1)
	m.mu.Unlock()

	go func() {
		defer m.workers.Done()
		m.execute(m.lifecycleCtx, status)
	}()
	return status
}

func (m *ScanManager) RunMaintenance(ctx context.Context, operation func(context.Context) error) error {
	m.mu.Lock()
	if !m.accepting || m.lifecycleCtx.Err() != nil || m.running || m.maintenance {
		m.mu.Unlock()
		return ErrMaintenanceBusy
	}
	m.maintenance = true
	m.mu.Unlock()

	operationCtx, cancel := context.WithCancel(ctx)
	stopLifecycleCancel := context.AfterFunc(m.lifecycleCtx, cancel)
	err := operation(operationCtx)
	stopLifecycleCancel()
	cancel()

	m.mu.Lock()
	m.maintenance = false
	if err == nil {
		m.lastStatus = ScanStatus{Status: ScanIdle}
	}
	m.mu.Unlock()
	return err
}

func (m *ScanManager) Status() ScanStatus {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.lastStatus
}

func (m *ScanManager) execute(ctx context.Context, status ScanStatus) {
	var errText string
	scanResult, err := m.indexer.Scan(ctx)
	if err != nil {
		errText = "media_scan_failed"
		m.logger.Error("scan media", "event", "media_scan_failed", "module", "scan", "result", "failure")
	} else {
		status.applyScanResult(scanResult)
	}

	if err == nil {
		thumbResult, thumbErr := m.thumbnails.GeneratePending(ctx, m.thumbnailBatch)
		status.applyThumbnailResult(thumbResult)
		if thumbErr != nil {
			errText = "thumbnail_batch_failed"
			m.logger.Error("generate thumbnails", "event", "thumbnail_batch_failed", "module", "thumbnail", "result", "failure")
		}
		m.logThumbnailFailures(thumbResult.Failures)
	}

	finished := time.Now().UTC()
	status.FinishedAt = &finished
	status.Error = errText
	if errText != "" {
		status.Status = ScanFailed
	} else {
		status.Status = ScanCompleted
	}

	m.mu.Lock()
	m.running = false
	m.lastStatus = status
	m.mu.Unlock()
}

func (m *ScanManager) logThumbnailFailures(failures []thumbnail.Failure) {
	counts := make(map[string]int)
	for _, failure := range failures {
		counts[failure.Code]++
	}
	for code, count := range counts {
		m.logger.Warn("thumbnail generation failed", "event", "thumbnail_item_failed", "module", "thumbnail", "result", "failure", "errorCode", code, "count", count)
	}
}

func (s *ScanStatus) applyScanResult(result indexing.ScanResult) {
	s.ScannedFiles = result.ScannedFiles
	s.IndexedFiles = result.IndexedFiles
	s.DeletedFiles = result.DeletedFiles
	s.MetadataExtracted = result.MetadataExtracted
	s.MetadataMissing = result.MetadataMissing
	s.MetadataFailed = result.MetadataFailed
	s.MetadataFallback = result.MetadataFallback
}

func (s *ScanStatus) applyThumbnailResult(result thumbnail.Result) {
	s.ThumbnailPending = result.Pending
	s.ThumbnailGenerated = result.Generated
	s.ThumbnailFailed = result.Failed
	s.ThumbnailError = thumbnailFailureSummary(result.Failures)
}

func thumbnailFailureSummary(failures []thumbnail.Failure) string {
	if len(failures) == 0 {
		return ""
	}

	summary := failures[0].Code
	if len(failures) > 1 {
		summary += fmt.Sprintf(" (+%d more)", len(failures)-1)
	}
	return summary
}
