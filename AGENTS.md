# AGENTS.md

This repository contains **家映**, a private family-media system for a home NAS and native Apple clients. The user communicates in Chinese and prefers practical, step-by-step explanations for deployment and platform behavior.

## Current Baseline

- Product baseline: `1.0.0-rc.2`.
- Apple version: `1.0.0 (4)` for iOS, iPadOS, and tvOS.
- NAS release platform: `linux/amd64`.
- Current priority: stability, documentation, reproducible deployment, and focused bug fixes.
- Do not add resume playback, Live Photo, search, favorites, recognition, multi-user access, or other broad features unless explicitly requested.

## Repository Layout

- `family-media-server`: Go HTTP server, SQLite media index, scanning, thumbnail generation, and NAS packaging.
- `FamilyMediaClient/Shared/FamilyMediaCore`: shared domain models, source services, stores, playback resolution/reporting, and tests.
- `FamilyMediaClient/Shared/FamilyMediaAppleUI`: UI infrastructure shared only where Apple platform behavior is genuinely common.
- `FamilyMediaClient/iOS`: iPhone/iPad SwiftUI app and tests.
- `FamilyMediaClient/TV`: tvOS SwiftUI app and tests.
- `docs`: unified release process and manual acceptance checklist.

Use the root [README](README.md) as the documentation index. Canonical details live in:

- `family-media-server/docs/client_api.md`
- `family-media-server/docs/nas_deployment.md`
- `FamilyMediaClient/docs/architecture.md`
- `FamilyMediaClient/docs/apple_installation.md`
- `docs/release_process.md`

## Architecture Boundaries

### Server

- `internal/domain`: media entities, query types, errors, and repository interfaces.
- `internal/application`: browse, timeline, scan, thumbnail, health, and cleanup use cases.
- `internal/infrastructure`: SQLite, filesystem, FFmpeg, HEIF conversion, and generated-data storage.
- `internal/interfaces`: HTTP handlers, routes, middleware, and static media delivery.
- `internal/platform`: config, logging, and build information.
- `internal/bootstrap`: dependency assembly only.

Keep HTTP concerns out of application/domain code. Keep SQLite, filesystem, and external command details behind infrastructure interfaces. The media index is generated data: during development an incompatible schema may be rebuilt instead of adding migration compatibility layers.

### Apple clients

- `FamilyMediaCore` owns source capabilities, networking, pagination, sorting, timeline state, playback state, request cancellation, Keychain/UserDefaults policy, and user-safe errors.
- iOS/iPadOS and tvOS keep separate navigation, layout, focus, remote, touch, and presentation code.
- Platform views receive `MediaSourceContext`; do not rediscover capabilities through source IDs or runtime casts.
- `MediaViewerCoordinator` owns sequence and photo navigation. Playback resolution/player/reporting belongs to the playback session/controller types.
- Family media and Jellyfin remain simultaneously configured. Switching sources must never clear the other source.

## Current Product Behavior

- Family media supports folder browsing, cursor pagination, sorting, year/month timeline, scans, generated-data cleanup, thumbnails, and original media delivery.
- Jellyfin supports login, libraries/folders, authenticated images, PlaybackInfo, Direct Play/HLS transcode, and playback session reporting.
- iPhone/iPad support touch paging, swipe-down dismissal, photo zoom/auto-advance pause, media information, and default-muted video with a mute toggle.
- tvOS uses focus/remote controls, timeline/sort pickers, photo auto-advance, media information, and audible video by default.
- The family-media server does not transcode client playback. Jellyfin owns incompatible-video transcoding.

## Engineering Rules

- Prefer small, evidence-based changes over broad rewrites or speculative abstractions.
- Preserve user changes in a dirty worktree and keep unrelated changes out of a commit.
- Use `rg`/`rg --files` for discovery and `apply_patch` for hand edits.
- Do not edit generated Xcode project settings directly when `project.yml` is the source of truth; regenerate with XcodeGen.
- Do not expose passwords, Jellyfin tokens, device IDs, real NAS addresses, media names, or private paths in logs, docs, tests, or diagnostics.
- Never delete original media. Cleanup operations may remove only generated index, thumbnails, and temporary transcode data.
- Do not add database compatibility code by default while the project remains in active development; rebuild generated SQLite data when the schema intentionally changes.
- Do not commit, tag, push, publish, or mutate a NAS unless the user explicitly asks. A request to implement normal repository changes does not authorize a Git tag or external deployment.

## Local Verification

Server:

```bash
cd family-media-server
go test ./...
go vet ./...
```

Shared client logic and release configuration:

```bash
cd FamilyMediaClient
swift test
python3 scripts/validate_release_configuration.py
```

Apple generic builds when Xcode is available:

```bash
cd FamilyMediaClient
xcodebuild -project FamilyMediaClient.xcodeproj -scheme FamilyMediaiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FamilyMediaClient.xcodeproj -scheme FamilyMediaTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build
```

Run the narrowest relevant tests during iteration, then the full applicable set before handoff. Always run `git diff --check`. Clearly report checks that could not run.

## NAS Build and Deployment

The known NAS architecture is x86_64. Keep the compatibility image tag `family-media-server:local`.

```bash
cd family-media-server
make nas-binary VERSION=1.0.0-rc.2
make release VERSION=1.0.0-rc.2
```

- First deployment or runtime dependency update: import the Docker tar and recreate the container while retaining `/data`.
- Normal server code update: replace the mounted executable and restart the same container.
- Required mappings: media library (read-only), `/data` (read-write), config (read-only), and external binary directory (read-only).
- `publicBaseURL` must be reachable from Apple devices; never use `localhost` for a NAS client deployment.
- Release outputs and checksums are ignored build artifacts and must not be committed.

Follow `docs/release_process.md` for release ordering. Create or move release tags only after the user completes `docs/manual_acceptance.md` and explicitly requests the Git operation.
