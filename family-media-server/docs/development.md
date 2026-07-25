# Development Guide

## Local Tooling

Required:

- Go 1.22 or newer
- Docker, only if building container images

Useful commands:

```bash
make fmt
make test
make run
make build
make nas-binary VERSION=1.0.0-rc.2
```

## Engineering Rules

- Domain packages must not import application, infrastructure, interfaces, platform, or bootstrap packages.
- Application packages may depend on domain interfaces and models.
- Infrastructure packages implement domain or application interfaces.
- Interface packages translate HTTP requests and responses, and should not contain business rules.
- Bootstrap is the only layer that wires concrete implementations together.
- Thumbnail application code should orchestrate status changes only; image/video generation belongs in infrastructure adapters.

## Current Implementation Boundaries

- SQLite is the active catalog repository; do not reintroduce in-memory full-library pagination.
- The infrastructure thumbnail pipeline owns format routing, native decoding, HEIF conversion, FFmpeg fallback, cancellation, and temporary-file cleanup. The application service stores only stable failure codes.
- Background scans are server-owned jobs and continue after a client stops polling, but are cancelled and awaited when the server shuts down. Do not start long-running work with `context.Background()` from an HTTP handler.
- The family server delivers original media and does not proxy or transcode Jellyfin playback.
- While the product remains in active development, rebuild generated SQLite data for intentional schema changes instead of maintaining migration compatibility layers.

## Diagnostics Rules

- Use stable `event`, `module` and `result` fields for operational logs.
- HTTP work uses the middleware operation ID to correlate access and handler events.
- Never log URLs, query strings, IPs, credentials, device IDs, media IDs, names or paths.
- Do not log raw FFmpeg, HEIF converter, SQLite or panic output. Convert user-visible and persisted failures to stable error codes.
- Do not emit per-second playback-style progress logs or one log per successful media file.

## Runtime Checks

The server validates key runtime dependencies during bootstrap:

- media root must exist and be readable
- thumbnail cache directory must be writable
- SQLite database directory must be writable
- `ffmpeg` is optional for startup, but video thumbnails fail without it
- `heif-convert` is optional for startup, but HEIC/HEIF thumbnails may fail without it
- IANA timezone data is embedded in the Go program; the image also installs `tzdata`

SQLite is embedded through the Go driver, so no standalone SQLite service or `sqlite3` command is required at runtime.

The canonical release and verification order is documented in the repository root at `docs/release_process.md`.
