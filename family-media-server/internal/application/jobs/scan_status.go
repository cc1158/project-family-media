package jobs

import "time"

type ScanState string

const (
	ScanIdle      ScanState = "idle"
	ScanRunning   ScanState = "running"
	ScanCompleted ScanState = "completed"
	ScanFailed    ScanState = "failed"
)

type ScanStatus struct {
	JobID              string     `json:"jobId"`
	Status             ScanState  `json:"status"`
	StartedAt          time.Time  `json:"startedAt"`
	FinishedAt         *time.Time `json:"finishedAt"`
	ScannedFiles       int        `json:"scannedFiles"`
	IndexedFiles       int        `json:"indexedFiles"`
	DeletedFiles       int        `json:"deletedFiles"`
	MetadataExtracted  int        `json:"metadataExtracted"`
	MetadataMissing    int        `json:"metadataMissing"`
	MetadataFailed     int        `json:"metadataFailed"`
	MetadataFallback   int        `json:"metadataFallback"`
	ThumbnailPending   int        `json:"thumbnailPending"`
	ThumbnailGenerated int        `json:"thumbnailGenerated"`
	ThumbnailFailed    int        `json:"thumbnailFailed"`
	ThumbnailError     string     `json:"thumbnailError,omitempty"`
	Error              string     `json:"error"`
}
