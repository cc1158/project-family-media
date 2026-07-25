package middleware

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAccessLogUsesOperationIDWithoutRequestSecrets(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	handler := Operation(AccessLog(logger, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	})))
	request := httptest.NewRequest(http.MethodGet, "/api/v1/browse/private-family-name?api_key=secret-token", nil)
	handler.ServeHTTP(httptest.NewRecorder(), request)

	text := output.String()
	for _, forbidden := range []string{"private-family-name", "secret-token", "api_key"} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("log leaked %q: %s", forbidden, text)
		}
	}
	var entry map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(output.Bytes()), &entry); err != nil {
		t.Fatal(err)
	}
	if entry["event"] != "http_request_completed" || entry["operationID"] == "" || entry["statusClass"] != "4xx" {
		t.Fatalf("entry = %#v", entry)
	}
}

func TestRecoverDoesNotLogPanicValue(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	handler := Operation(Recover(logger, http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("private/media/path.jpg")
	})))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d", response.Code)
	}
	if strings.Contains(output.String(), "private/media/path.jpg") {
		t.Fatalf("panic value leaked: %s", output.String())
	}
}
