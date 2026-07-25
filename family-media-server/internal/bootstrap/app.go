package bootstrap

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	applicationhealth "family-media-server/internal/application/health"
	"family-media-server/internal/application/indexing"
	"family-media-server/internal/application/jobs"
	"family-media-server/internal/application/maintenance"
	applicationmedia "family-media-server/internal/application/media"
	"family-media-server/internal/application/thumbnail"
	mediasqlite "family-media-server/internal/infrastructure/media/sqlite"
	"family-media-server/internal/infrastructure/metadata"
	thumbnailffmpeg "family-media-server/internal/infrastructure/thumbnail/ffmpeg"
	thumbnailheif "family-media-server/internal/infrastructure/thumbnail/heif"
	thumbnailimaging "family-media-server/internal/infrastructure/thumbnail/imaging"
	thumbnailpipeline "family-media-server/internal/infrastructure/thumbnail/pipeline"
	httpapi "family-media-server/internal/interfaces/http"
	"family-media-server/internal/interfaces/http/handler"
	"family-media-server/internal/platform/config"
	"family-media-server/internal/platform/health"
	"family-media-server/internal/platform/logger"
)

type App struct {
	Config config.Config
	Logger *slog.Logger
	Server *http.Server
	Jobs   *jobs.Group
	Scans  *jobs.ScanManager
}

func New(lifecycleCtx context.Context, configPath string) (*App, error) {
	log := logger.New()

	cfg, err := config.Load(configPath)
	if err != nil {
		return nil, err
	}
	if err := health.ValidateEnvironment(cfg, log); err != nil {
		return nil, err
	}

	repository, err := mediasqlite.Open(cfg.Index.DBPath)
	if err != nil {
		return nil, err
	}
	if repository.IndexRebuilt() {
		log.Warn("media index schema changed; generated index was rebuilt", "event", "media_index_rebuilt", "module", "database", "result", "success", "action", "scan_media")
	}
	catalogService := applicationmedia.NewCatalogService(repository, cfg.Server.PublicBaseURL)
	metadataExtractor := metadata.NewExtractor()
	indexer := indexing.NewScannerWithMetadata(cfg.Media.RootDir, repository, metadataExtractor)
	imageGenerator := thumbnailimaging.NewGenerator(cfg.Thumbnail.MaxSide)
	ffmpegGenerator := thumbnailffmpeg.NewGenerator(cfg.Thumbnail.MaxSide)
	thumbnailGenerator := thumbnailpipeline.NewGenerator(imageGenerator, ffmpegGenerator, thumbnailheif.NewConverter())
	thumbnailer := thumbnail.NewService(cfg.Media.RootDir, cfg.Thumbnail.CacheDir, thumbnailGenerator, repository)
	scanManager := jobs.NewScanManager(lifecycleCtx, indexer, thumbnailer, time.Duration(cfg.Scan.IntervalSeconds)*time.Second, cfg.Thumbnail.BatchSize, log)
	cleaner := maintenance.NewService(
		repository,
		cfg.Media.RootDir,
		cfg.Index.DBPath,
		cfg.Thumbnail.CacheDir,
		cfg.Transcode.WorkDir,
	)
	healthService := applicationhealth.NewService(cfg, scanManager)

	healthHandler := handler.NewHealthHandler(healthService)
	catalogHandler := handler.NewCatalogHandler(catalogService, catalogService, log)
	adminHandler := handler.NewAdminHandler(scanManager, thumbnailer, cleaner)
	router := httpapi.NewRouter(healthHandler, catalogHandler, adminHandler, httpapi.StaticMediaConfig{
		RootDir:  cfg.Media.RootDir,
		ThumbDir: cfg.Thumbnail.CacheDir,
	})

	return &App{
		Config: cfg,
		Logger: log,
		Server: httpapi.NewServer(cfg, router, log),
		Jobs:   jobs.NewGroup(log, scanManager),
		Scans:  scanManager,
	}, nil
}

func (a *App) StartBackgroundJobs(ctx context.Context) {
	a.Jobs.Start(ctx)
}
