package transcode

import "context"

type Request struct {
	MediaPath string
	Profile   string
}

type Service interface {
	Prepare(ctx context.Context, request Request) (string, error)
}
