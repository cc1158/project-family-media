package httpapi

import (
	"net/http"

	"family-media-server/internal/interfaces/http/handler"
	v1 "family-media-server/internal/interfaces/http/v1"
)

type StaticMediaConfig struct {
	RootDir  string
	ThumbDir string
}

func NewRouter(health *handler.HealthHandler, catalog *handler.CatalogHandler, admin *handler.AdminHandler, media StaticMediaConfig) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health.Check)
	v1.RegisterRoutes(mux, catalog, admin)
	mux.Handle("/media/original/", http.StripPrefix("/media/original/", http.FileServer(http.Dir(media.RootDir))))
	mux.Handle("/media/thumbnails/", http.StripPrefix("/media/thumbnails/", http.FileServer(http.Dir(media.ThumbDir))))
	return mux
}
