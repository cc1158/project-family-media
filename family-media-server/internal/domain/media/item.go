package media

import "time"

type Kind string

const (
	KindVideo Kind = "video"
	KindPhoto Kind = "photo"
)

type ThumbnailStatus string

const (
	ThumbnailPending ThumbnailStatus = "pending"
	ThumbnailReady   ThumbnailStatus = "ready"
	ThumbnailFailed  ThumbnailStatus = "failed"
)

type Item struct {
	ID              string          `json:"id"`
	Name            string          `json:"name"`
	Kind            Kind            `json:"kind"`
	Size            int64           `json:"size"`
	Modified        time.Time       `json:"modified"`
	CapturedAt      *time.Time      `json:"capturedAt,omitempty"`
	TimelineDate    *time.Time      `json:"timelineDate,omitempty"`
	IndexedAt       time.Time       `json:"-"`
	URL             string          `json:"url"`
	ThumbnailURL    string          `json:"thumbnailURL"`
	MediaPath       string          `json:"mediaPath"`
	ThumbnailStatus ThumbnailStatus `json:"thumbnailStatus"`
	ContainerID     string          `json:"containerID,omitempty"`
	IsContainer     bool            `json:"isContainer,omitempty"`
	SortTime        time.Time       `json:"-"`
	ThumbnailPath   string          `json:"-"`
	LastError       string          `json:"-"`
}

type TimelineSort string

const (
	TimelineSortCapturedDesc TimelineSort = "captured_desc"
	TimelineSortCapturedAsc  TimelineSort = "captured_asc"
)

type TimelineQuery struct {
	Kind        Kind
	ContainerID string
	TimeZone    string
	Sort        TimelineSort
}

type TimelineBrowseQuery struct {
	TimelineQuery
	Bucket string
	Limit  int
	Cursor string
}

type TimelineIndex struct {
	DateSemantics string         `json:"dateSemantics"`
	TimeZone      string         `json:"timeZone"`
	Years         []TimelineYear `json:"years"`
}

type TimelineYear struct {
	Key                string          `json:"key"`
	Count              int             `json:"count"`
	CoverThumbnailURLs []string        `json:"coverThumbnailURLs"`
	Months             []TimelineMonth `json:"months"`
}

type TimelineMonth struct {
	Key                string   `json:"key"`
	Count              int      `json:"count"`
	CoverThumbnailURLs []string `json:"coverThumbnailURLs"`
}
