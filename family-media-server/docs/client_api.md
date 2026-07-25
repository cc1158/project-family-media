# Client API Guide

This document is for iOS and tvOS clients.

The client should use URLs returned by the server. Do not build media or thumbnail URLs on the client.

## Base URL

The server base URL is configured by the user, for example:

```text
http://nas.local:8080
```

All API examples below use this base URL.

## Health Check

```http
GET /healthz
```

Response:

```json
{
  "status": "ok",
  "apiVersion": 2,
  "capabilities": [
    "folder_browse",
    "generated_data_clear",
    "thumbnail_self_heal",
    "browse_sort",
    "timeline_index",
    "timeline_browse"
  ]
}
```

Current Apple clients require API version `2` plus `folder_browse`, `generated_data_clear`, and `browse_sort`. A reachable server that omits these fields is an older installation and should be updated before browsing.

Current servers also include optional build identity information:

```json
{
  "build": {
    "version": "1.0.0-rc.2",
    "commit": "提交号",
    "builtAt": "构建时间",
    "source": "external"
  }
}
```

`source` is `external` for the NAS-mounted executable, `bundled` for the image fallback, and `development` for local runs. Clients must treat the entire object as optional for compatibility with older servers.

The optional `checks.heif` entry reports whether the runtime image contains the HEIC/HEIF converter. A missing converter degrades thumbnail support but does not make catalog browsing unavailable.

Client usage:

- Settings screen connection test
- Initial server availability check

## Folder Browsing

The Apple clients use the folder-aware endpoint for normal browsing:

```http
GET /api/v1/browse
```

Query parameters:

| Name | Required | Description |
|---|---:|---|
| `containerID` | No | Omit at the source root. Pass the `id` of a returned container to enter it. |
| `kind` | No | `video` or `photo`. Omit for all media. |
| `limit` | No | Page size. Default is `50`, maximum is `200`. |
| `cursor` | No | Opaque cursor returned by the previous page. |
| `sort` | No | `captured_desc` (default), `captured_asc`, `name_asc`, `name_desc`, or `indexed_desc`. |

The server derives containers from paths relative to the configured media root. It preserves every directory level and does not move or rename files on the NAS. Files located directly under the media root appear in a virtual container named `未分类`.

Container response example:

```json
{
  "id": "opaque-container-id",
  "name": "幼儿园",
  "kind": "container",
  "containerID": "opaque-container-id",
  "isContainer": true,
  "thumbnailURL": "http://nas.local:8080/media/thumbnails/ab/cd/cover.jpg",
  "thumbnailStatus": "ready"
}
```

Container IDs and cursors are opaque. Clients must return them unchanged and must not derive filesystem paths from them. A container can have no cover; in that case the client should display a folder placeholder.

Within each page, folders are returned before files and use case-insensitive natural-name ordering; for example, `第2集` precedes `第10集`. The virtual `未分类` folder is shown after physical root folders. The selected `sort` applies only to media files, so folder positions do not jump when media is added. `kind=video` and `kind=photo` keep the same directory hierarchy but only include folders that contain matching descendants.

Captured-time sorting uses extracted photo/video metadata and falls back to file-modified time when metadata is unavailable. `indexed_desc` represents the time the server first indexed the item. A cursor is valid only with the same `kind`, `containerID`, and `sort`; changing the sort requires restarting at the first page without a cursor.

## Timeline Browsing

Clients that see both `timeline_index` and `timeline_browse` can offer year and month views. First load the lightweight index:

```http
GET /api/v1/timeline/index?kind=photo&timeZone=Asia%2FShanghai&sort=captured_desc
```

`containerID` is optional and limits the index recursively to that folder. The response contains year/month counts and up to four ready thumbnail URLs for summary cards. Empty periods are omitted. Dates use captured metadata when available and the file-modified fallback otherwise.

Load an individual month through the normal browse response shape:

```http
GET /api/v1/browse?scope=recursive&bucket=2026-07&timeZone=Asia%2FShanghai&sort=captured_desc&limit=50
```

Timeline browsing accepts only `captured_desc` and `captured_asc`. Returned media include `timelineDate`, the effective date used for grouping. Cursors are scoped to the container, filter, month, direction, and timezone and remain opaque.

The standalone Go binary embeds the IANA timezone database, so values such as `Asia/Shanghai` work even when the host image does not provide `/usr/share/zoneinfo`. Invalid names return `400 invalid_time_zone`.

## Flat Media Lists

The legacy flat endpoints remain available for administrative or older client use:

```http
GET /api/v1/media
GET /api/v1/photos
GET /api/v1/videos
```

Query parameters:

| Name | Required | Description |
|---|---:|---|
| `limit` | No | Page size. Default is `50`, maximum is `100`. |
| `cursor` | No | Cursor returned by the previous page. Omit for the first page. |
| `sort` | No | Sort mode. Supported values are `captured_desc`, `modified_desc`, `indexed_desc`, and `name_asc`. Default is `captured_desc`. |
| `group` | No | Grouping mode. Supported value is `month`. Valid with time-based sort modes, not with `name_asc`. |

Default ordering is newest first by the server's media sort time, then `id` descending for stable pagination. The server uses captured/shot time when metadata is available and keeps file modified time as the fallback.

The client should keep using the same `sort` value when requesting the next page with `cursor`. If the user changes sort mode, restart from the first page and omit `cursor`.

Example:

```http
GET /api/v1/media?limit=50
```

Next page:

```http
GET /api/v1/media?limit=50&sort=captured_desc&cursor=NEXT_CURSOR
```

Response:

```json
{
  "items": [
    {
      "id": "stable-id",
      "name": "IMG_001.jpg",
      "kind": "photo",
      "size": 123456,
      "modified": "2026-05-19T12:00:00Z",
      "capturedAt": "2026-05-19T11:58:00Z",
      "url": "http://nas.local:8080/media/original/2026/IMG_001.jpg",
      "thumbnailURL": "http://nas.local:8080/media/thumbnails/ab/cd/stable-id.jpg",
      "mediaPath": "2026/IMG_001.jpg",
      "thumbnailStatus": "ready"
    }
  ],
  "groups": [
    {
      "key": "2026-05",
      "title": "2026-05",
      "startIndex": 0,
      "count": 1
    }
  ],
  "nextCursor": "encoded-cursor",
  "hasMore": true
}
```

## Media Item Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable media ID. |
| `name` | string | File name. |
| `kind` | string | `photo` or `video`. |
| `size` | number | File size in bytes. |
| `modified` | string | File modified time in RFC3339 format. |
| `capturedAt` | string | Optional captured/shot time in RFC3339 format. Omitted when metadata is unavailable. |
| `timelineDate` | string | Effective grouping date returned by timeline browse requests. |
| `url` | string | Full original media URL. Use this for photo display or video playback. |
| `thumbnailURL` | string | Full thumbnail URL. Empty when thumbnail is not available. |
| `mediaPath` | string | NAS-root-relative path. Display/debug only; do not use it to build URLs. |
| `thumbnailStatus` | string | `pending`, `ready`, or `failed`. |
| `containerID` | string | Opaque navigation context for a container. Omitted for playable media. |
| `isContainer` | boolean | `true` for a navigable folder. Omitted for playable media. |

## Media Groups

When `group=month` is present, the response includes `groups`. Each group applies to the current page only and points into `items` by `startIndex` and `count`. A month can continue on the next page, so clients should render groups page by page or merge adjacent groups with the same `key`.

## Thumbnail Handling

Client behavior:

| Status | `thumbnailURL` | Client behavior |
|---|---|---|
| `ready` | non-empty | Load and display `thumbnailURL`. |
| `pending` | empty | Show placeholder. Do not load original media as thumbnail. |
| `failed` | empty | Show failed/default placeholder. |

The client should refresh or reload the list after a scan completes to get newly generated thumbnails. During each scan, the server checks whether files recorded as `ready` still exist in the thumbnail cache. Missing files are reset and regenerated, and all pending batches are drained before the scan completes. On the first scan after a server restart, historical failures are retried once so newly added format support can repair thumbnails created by an older server image without repeatedly processing permanently damaged files.

## Opening Media

Use the `url` field from the media item.

Photo:

- Open `url` in the photo detail viewer.

Video:

- Pass `url` to the system video player.

The client should not concatenate `/media/original` or any path manually.

## Manual Scan

Trigger scan:

```http
POST /api/v1/admin/scan
```

Response:

```json
{
  "jobId": "scan-20260519-120000",
  "status": "running"
}
```

Client usage:

- Settings screen "Scan Media Library" button
- The request returns immediately
- If another scan is already running, the server returns the current running job

## Scan Status

```http
GET /api/v1/admin/scan/status
```

Response:

```json
{
  "jobId": "scan-20260519-120000",
  "status": "completed",
  "startedAt": "2026-05-19T12:00:00Z",
  "finishedAt": "2026-05-19T12:00:05Z",
  "scannedFiles": 1200,
  "indexedFiles": 20,
  "deletedFiles": 2,
  "metadataExtracted": 1100,
  "metadataMissing": 90,
  "metadataFailed": 10,
  "metadataFallback": 100,
  "thumbnailPending": 100,
  "thumbnailGenerated": 90,
  "thumbnailFailed": 10,
  "thumbnailError": "kids/broken.mp4: ffmpeg not found",
  "error": ""
}
```

Client MVP should rely only on:

- `jobId`
- `status`
- `startedAt`
- `finishedAt`
- `error`

Other counters are useful for display, but should be treated as optional.

Statuses:

| Status | Meaning |
|---|---|
| `idle` | No scan has run since server startup. |
| `running` | Scan or thumbnail generation is running. |
| `completed` | Last scan completed successfully. |
| `failed` | Last scan failed. Check `error`. |

## Recommended Client Flow

Initial setup:

```text
GET /healthz
```

Family-media source root:

```text
GET /api/v1/browse?limit=50&sort=captured_desc
```

Infinite scroll:

```text
if hasMore == true:
  GET /api/v1/browse?limit=50&sort=captured_desc&cursor=nextCursor
```

Photos tab:

```text
GET /api/v1/browse?kind=photo&limit=50&sort=captured_desc
```

Videos tab:

```text
GET /api/v1/browse?kind=video&limit=50&sort=captured_desc
```

Settings scan:

```text
POST /api/v1/admin/scan
poll GET /api/v1/admin/scan/status
refresh media list when status becomes completed
```

## Regenerate A Thumbnail

If a thumbnail is not suitable, the client can ask the server to regenerate it.

```http
POST /api/v1/admin/media/{id}/thumbnail/regenerate
```

Request body is optional.

For videos, the client may provide a custom frame offset:

```json
{
  "timeOffsetSeconds": 12
}
```

Response:

```json
{
  "id": "media-id",
  "thumbnailStatus": "ready"
}
```

Client usage:

- Detail screen "Regenerate Thumbnail"
- Debug/admin action in MVP
- Refresh the list or the current item after the request completes

## Clear Generated Data

The settings screen can clear data generated by the family-media service:

```http
POST /api/v1/admin/data/clear
Content-Type: application/json

{
  "rescan": true
}
```

The operation clears media index records, thumbnail cache files, and transcode temporary files. It never deletes original photos or videos, `config.yaml`, client settings, or Jellyfin data. The server rejects generated-data paths that overlap the media root or contain the open SQLite index.

With `rescan=true`, the server starts a new media scan after cleanup and returns its job information:

```json
{
  "status": "cleared",
  "clearedDirectories": 2,
  "scan": {
    "jobId": "scan-20260719-120000",
    "status": "running"
  }
}
```

Cleanup and scanning are mutually exclusive. A request made while a scan or another cleanup is active returns HTTP `409` with `media_scan_in_progress`.

## Error Handling

Common responses:

| HTTP Status | Meaning | Client behavior |
|---:|---|---|
| `200` | Success | Use response normally. |
| `202` | Scan accepted | Show scanning state. |
| `400` | Invalid request, such as bad cursor | Restart list from first page. |
| `500` | Server error | Show retry option. |

Error response shape:

```json
{
  "error": "invalid_cursor"
}
```
