package jobs

import (
	"context"
	"log/slog"
	"sync"
)

type Runner interface {
	Name() string
	Run(ctx context.Context) error
}

type Group struct {
	runners []Runner
	logger  *slog.Logger
	wg      sync.WaitGroup
}

func NewGroup(logger *slog.Logger, runners ...Runner) *Group {
	return &Group{
		runners: runners,
		logger:  logger,
	}
}

func (g *Group) Start(ctx context.Context) {
	for _, runner := range g.runners {
		runner := runner
		g.wg.Add(1)
		go func() {
			defer g.wg.Done()
			g.logger.Info("background job started", "event", "background_job_started", "module", "jobs", "result", "success", "job", runner.Name())
			if err := runner.Run(ctx); err != nil && ctx.Err() == nil {
				g.logger.Error("background job stopped with error", "event", "background_job_failed", "module", "jobs", "result", "failure", "job", runner.Name())
			}
		}()
	}
}

func (g *Group) Wait(ctx context.Context) error {
	done := make(chan struct{})
	go func() {
		g.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
