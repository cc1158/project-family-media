package jobs

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"
)

func TestGroupWaitsForRunnerShutdown(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	runner := &blockingRunner{started: make(chan struct{})}
	group := NewGroup(slog.Default(), runner)
	group.Start(ctx)
	<-runner.started
	cancel()

	waitCtx, waitCancel := context.WithTimeout(context.Background(), time.Second)
	defer waitCancel()
	if err := group.Wait(waitCtx); err != nil {
		t.Fatalf("wait: %v", err)
	}
}

func TestGroupWaitHonorsDeadline(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	runner := &blockingRunner{started: make(chan struct{}), ignoreCancellation: true}
	group := NewGroup(slog.Default(), runner)
	group.Start(ctx)
	<-runner.started

	waitCtx, waitCancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer waitCancel()
	if err := group.Wait(waitCtx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("wait error = %v", err)
	}
	runner.release <- struct{}{}
}

type blockingRunner struct {
	started            chan struct{}
	ignoreCancellation bool
	release            chan struct{}
}

func (r *blockingRunner) Name() string { return "blocking" }

func (r *blockingRunner) Run(ctx context.Context) error {
	if r.release == nil {
		r.release = make(chan struct{})
	}
	close(r.started)
	if r.ignoreCancellation {
		<-r.release
		return nil
	}
	<-ctx.Done()
	return ctx.Err()
}
