package v1

import (
	"net/http"

	"family-media-server/internal/interfaces/http/handler"
)

func RegisterRoutes(mux *http.ServeMux, catalog *handler.CatalogHandler, admin *handler.AdminHandler) {
	mux.HandleFunc("GET /api/v1/media", catalog.Media)
	mux.HandleFunc("GET /api/v1/videos", catalog.Videos)
	mux.HandleFunc("GET /api/v1/photos", catalog.Photos)
	mux.HandleFunc("GET /api/v1/browse", catalog.Browse)
	mux.HandleFunc("GET /api/v1/timeline/index", catalog.TimelineIndex)
	mux.HandleFunc("POST /api/v1/admin/scan", admin.TriggerScan)
	mux.HandleFunc("GET /api/v1/admin/scan/status", admin.ScanStatus)
	mux.HandleFunc("POST /api/v1/admin/data/clear", admin.ClearGeneratedData)
	mux.HandleFunc("POST /api/v1/admin/media/{id}/thumbnail/regenerate", admin.RegenerateThumbnail)
}
