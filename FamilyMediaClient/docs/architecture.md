# FamilyMedia Client Architecture

## Scope

客户端包含 tvOS 与 iOS 两个 App Target，同时访问家庭媒体服务和 Jellyfin。客户端不直接访问 SMB、NFS 或 NAS 文件系统。

## Layers

```text
FamilyMediaClient
├── Shared/FamilyMediaCore
│   ├── Sources/FamilyMediaCore/Models
│   │   ├── MediaItem / MediaPage
│   │   ├── MediaSorting / MediaSortPreferenceStore
│   │   ├── HealthStatus
│   │   ├── ScanStatus
│   │   ├── ThumbnailRegeneration
│   │   ├── MediaViewerSession
│   │   └── PlaybackSettings
│   ├── Sources/FamilyMediaCore/MediaViewer
│   │   ├── MediaPlaybackController
│   │   ├── MediaPlaybackReportSequencer
│   │   ├── MediaPlaybackSessionController
│   │   ├── MediaPlaybackSnapshot
│   │   ├── MediaViewerCoordinator
│   │   └── MediaThumbnailPresentation
│   ├── Sources/FamilyMediaCore/Diagnostics
│   │   ├── ClientDiagnosticsReport
│   │   └── ClientEventLog
│   ├── Sources/FamilyMediaCore/MediaSources
│   │   └── MediaSourceContext / MediaSourceRegistry
│   ├── Sources/FamilyMediaCore/Configuration
│   │   ├── ClientAppConfiguration
│   │   ├── ServerAddressNormalizer
│   │   └── ServerConfigurationStore
│   ├── Sources/FamilyMediaCore/Networking
│   │   ├── APIConfiguration
│   │   ├── APIClient
│   │   ├── APIEndpoint
│   │   └── HTTPClient
│   ├── Sources/FamilyMediaCore/Services
│   │   ├── MediaService / MediaServicing
│   │   ├── JellyfinAPIClient
│   │   ├── JellyfinCatalogService
│   │   ├── JellyfinPlaybackService
│   │   ├── JellyfinPlaybackURLBuilder
│   │   └── JellyfinService (Facade)
│   ├── Sources/FamilyMediaCore/Stores
│   │   ├── MediaLibraryStore
│   │   ├── MediaTimelineStore
│   │   ├── SettingsStore
│   │   └── ThumbnailRegenerationStore
│   ├── Sources/FamilyMediaCore/Settings
│   │   └── ScanStatusPresentation
│   ├── Sources/FamilyMediaCore/State
│   │   ├── AppMessage / AppMessageStyle
│   │   └── Loadable
│   ├── Sources/FamilyMediaCore/Support
│   │   └── JSONDecoder+FamilyMedia
│   ├── Sources/FamilyMediaCore/Utilities
│   │   └── DelayedActionScheduler
│   └── Tests/FamilyMediaCoreTests
├── TV/FamilyMediaTV
│   ├── Sources/FamilyMediaTV/App
│   │   └── FamilyMediaTVApp
│   ├── Sources/FamilyMediaTV/Features
│   │   ├── Home
│   │   ├── MediaGrid
│   │   ├── MediaViewer
│   │   └── Settings (screen / sections)
│   ├── Sources/FamilyMediaTV/SharedUI
│   │   └── FamilyMediaTVTheme / MediaThumbnailView / ContentUnavailableView
│   ├── Sources/FamilyMediaTV/Utilities
│   └── Resources/Info.plist
├── iOS/FamilyMediaiOS
│   ├── Sources/FamilyMediaiOS/App
│   │   ├── FamilyMediaiOSApp
│   │   └── RootTabView
│   ├── Sources/FamilyMediaiOS/Features
│   │   ├── MediaLibrary / source home
│   │   ├── MediaViewer
│   │   └── Settings (overview / details / components)
│   ├── Sources/FamilyMediaiOS/SharedUI
│   │   └── MediaThumbnailView / EmptyStateView
│   ├── Sources/FamilyMediaiOS/Utilities
│   └── Resources/Info.plist
├── Shared/FamilyMediaAppleUI
│   ├── AppDependencies
│   ├── MediaBrowseSessionController
│   ├── CachedRemoteImage
│   ├── MediaImagePipeline / ImageMemoryCache
│   └── shared Apple presentation infrastructure
└── project.yml
```

## Dependency Direction

`TV/FamilyMediaTV` and `iOS/FamilyMediaiOS` depend on `FamilyMediaCore`. Their shared `AppDependencies` is the single composition root for configuration stores, refresh centers, concrete services and `MediaSourceRegistry`; platform entry points only select launch behavior. Each browsing flow receives one `MediaSourceContext`, which bundles catalog, playback resolver, optional playback reporting, and optional family-media administration without runtime type inference.

`MediaBrowseSessionController` is the shared Apple presentation boundary for one open catalog. It owns the directory and timeline stores, forwards their change notifications without copying page data, and coordinates initial preparation, mode changes, source refresh, foreground recovery, manual reload, viewer return and anchor preservation. iOS keeps scroll and sheet state; tvOS keeps focus and remote state. Neither platform view reimplements the loading sequence.

Both sources now expose the same container-navigation shape. Jellyfin maps libraries and folders to containers; the family-media source calls `/api/v1/browse` and maps the NAS-relative directory hierarchy to containers. `MediaSourceContext.catalogStructure` describes whether a root container is a directory tree or a media-library root, so platform views obtain “文件夹/媒体库” copy without testing a source ID. The existing recursive iOS and tvOS library views therefore navigate either source without source-specific UI branching. Root-level family files appear inside the server-provided virtual `未分类` container; the client never infers paths or moves files and treats container IDs and pagination cursors as opaque values.

Family-media maintenance is an explicit server-owned capability. iOS and tvOS require destructive confirmation before calling `/api/v1/admin/data/clear`, explain that original NAS media is preserved, and offer either cleanup alone or cleanup followed by a scan. A successful cleanup invalidates visible family-media libraries immediately. It does not clear either server address or the independent Jellyfin session.

Family-media health responses also act as a compatibility handshake. `MediaService` requires API version 2 plus folder-browse, generated-data-clear, and browse-sort capabilities before marking the source usable. A reachable legacy server is represented separately from a transient network outage: its source card says that an update is required, blocks navigation into an incompatible library, and routes the user to settings. Jellyfin health remains independent and is not subject to the family-server contract.

Sorting is part of the paged catalog request rather than a client-side rearrangement. `MediaLibraryStore` sends one stable sort through every page, invalidates older generations when the user changes it, and persists the choice by source and media filter. Family media exposes captured-time, natural-name, and indexed-time rules; Jellyfin maps source-appropriate choices to `SortName` or `DateCreated`. Library roots and playlists retain Jellyfin's structural ordering. Platform views own only the navigation-bar menu and focus or scroll restoration.

Family media additionally exposes a capability-gated recursive timeline. `MediaTimelineStore` owns directory/month/year mode persistence, the lightweight year/month index, per-month lazy pagination, request generations, and chronological viewer order. The server alone resolves captured-time fallback and timezone month boundaries; Apple UI never groups a partially loaded page locally. iPhone/iPad render a segmented mode picker, sticky month sections and calendar jump menu, while tvOS uses focusable mode and direction menus with remote-friendly grids. `MediaSourceContext.timeline` is optional, so Jellyfin and older family servers remain directory-only.

`MediaSourceAvailabilityStore` checks both sources concurrently and exposes a shared state for unchecked, checking, available, authentication-required, and temporarily unavailable conditions. Authentication requirements redirect to settings, while a transient connection failure still permits opening the normal retry screen. Cancelled checks return to an unchecked state rather than showing a false offline error. If another refresh is requested while a check is active, the store coalesces those requests into one follow-up pass instead of starting competing NAS requests or dropping the newest configuration state.

Jellyfin uses a thin `JellyfinService` facade. `JellyfinAPIClient` owns authenticated requests, 401 cleanup, reverse-proxy URL handling, and session storage; catalog mapping and playback policy/reporting live in separate services.

Server addresses are normalized to HTTP or HTTPS endpoints before persistence. User-info, query-bearing, fragment-bearing, and unsupported-scheme addresses are rejected. Changing the normalized Jellyfin endpoint clears the previous server session, while cosmetic trailing-slash changes preserve it. A delayed 401 only clears the token used by that request and cannot remove a newer login.

Authenticated playback URLs preserve configured reverse-proxy subpaths for both slash-prefixed and plain relative transcoding paths. Absolute playback URLs must match the configured scheme, host, and effective port before the access token is appended, preventing credentials from being attached to an unrelated origin.

Playback is split into two levels: `MediaPlaybackSessionController` owns asynchronous resolution, cancellation, AVPlayer setup, state, and one-time lifecycle reporting. It publishes one `MediaPlaybackSnapshot` containing the current player, state, mute choice and timeline; `isPlaying` is derived from that state rather than mirrored independently. `MediaViewerCoordinator` subscribes once and exposes compatibility accessors while continuing to own only the media sequence, navigation, photo timing, autoplay limits, and thumbnail administration. The shared state machine is `idle → preparing → buffering(method) → playing(method) / paused(method)`, with failures represented by `failed(failure)`. It also observes `AVPlayer.timeControlStatus`, so stalls, recovery, and system-driven pauses update the shared UI state instead of leaving stale controls on screen.

Reaching the configured autoplay limit pauses sequence advancement while keeping the current item as the viewer anchor. The user can start a new autoplay window or return to the library; returning restores the grid to that current item instead of the item that originally opened the viewer. Reaching the actual end of the sequence still returns directly because there is no later content to continue.

Viewer navigation publishes one atomic event containing a sequence number, media ID, index, and initial/manual/automatic origin. `ViewerChromeController` in the shared Apple UI is the only owner of control visibility and its auto-hide timer. iOS/iPadOS and tvOS translate touch, remote, focus, panels, and accessibility changes into controller events without writing visibility flags themselves. Manual navigation reveals the controls, while automatic photo/video advancement remains in `automaticTransition` through loading, preparation, and buffering; a playback failure exits that state and reveals actionable controls. Media callbacks and timer completions are scoped to the current media ID and generation, so late work from an earlier item cannot flash or hide the current chrome.

Playback failure state carries a recovery kind in addition to household-facing text. Temporary network and runtime failures offer both “重新尝试” and a way back to the library; an expired Jellyfin session explains that sign-in is required and does not present a useless retry loop; a server-declared unsupported format offers only a return action. AVPlayer and Jellyfin server diagnostics are normalized before presentation, so system error strings and raw HTTP status codes do not leak into the living-room UI.

A retry remains local to the currently open viewer and never becomes persisted watch history. Runtime failure captures the interrupted position and duration; retry requests a fresh direct-play or Jellyfin PlaybackInfo resolution, waits for the replacement AVPlayer item to become ready, seeks roughly two seconds before the interruption, and only then resumes. The new Jellyfin lifecycle is reported in order as started followed by the recovered position. First playback, media navigation, viewer dismissal, and positions below five seconds clear the retry context so one item's position cannot leak into another.

`MediaBufferingWatchdog` owns the boundary between a recoverable stall and indefinite waiting. It arms only while AVPlayer reports `waitingToPlayAtSpecifiedRate`; thirty continuous seconds without returning to playing or paused converts the session to a retryable household-facing failure, captures the current recovery position, clears the player, and sends one stopped report. Playing, pausing, app interruption, media replacement, failure, and viewer dismissal all disarm the watchdog. The timer is injected through `DelayedActionScheduling`, allowing both the timer rules and the full playback-session transition to be tested without sleeping for thirty seconds.

The playback controller samples the local position every half second, tracks duration and loaded ranges, and keeps the 15-second Jellyfin progress-report cadence separate from UI updates. This gives the stopped report the latest local position even when playback ends before the first periodic server report. Seeking is clamped to the known duration, uses a small tolerance suitable for HLS, suppresses stale periodic positions while the seek is in flight, and immediately reports the resulting position after playback has started.

iOS and tvOS share the image pipeline in `Shared/FamilyMediaAppleUI`. `CachedRemoteImage` is only the SwiftUI phase adapter, `MediaImagePipeline` owns request coalescing, cancellation, transfer and decode, and `ImageMemoryCache` owns limits plus memory-warning cleanup. The pipeline keeps a bounded in-memory cache and downsamples list thumbnails to at most 800 pixels—enough for the current Retina and tvOS card sizes—while full-screen photos use at most 4096 pixels before creating `UIImage` instances. This avoids decoding original artwork or phone photos at unnecessarily large dimensions. Concurrent requests for the same URL, pixel size, and cache version share one transfer. Cancelling one visible view does not interrupt other waiters, while cancelling the final waiter also cancels the underlying transfer.

The iOS photo viewer uses a native `UIScrollView` zoom surface for pinch, pan, and double-tap zoom. At the original zoom scale, a dedicated navigation recognizer hands horizontal paging and downward dismissal back to the full-screen viewer; once zoomed, all dragging remains inside the scroll view for inspection. While the user keeps a photo zoomed, photo auto-advance is suspended and resumes after returning to the normal scale. Both platforms expose an in-place retry when the original photo cannot be loaded; tvOS also fades between viewer items unless Reduce Motion is enabled.

The iOS viewer keeps session orchestration separate from presentation. `MediaViewerScreen` coordinates lifecycle and chrome policy, `MediaViewerInteractionSurface` composes current and adjacent content, and dedicated paging/dismiss presentation states own their drag transforms and transition intent. `ViewerNavigationGesturePolicy` is the small composition boundary for common availability and photo gesture arbitration; horizontal paging and downward dismissal remain independent policies. Transport/timeline rendering and transient playback feedback live in dedicated views. Horizontal drags page in place; a downward drag scales the current media over a transparent presentation background and dismisses through the normal viewer lifecycle. UIKit only arbitrates the photo scroll view's own pan against the viewer navigation recognizer at the original zoom scale; taps, zoom gestures, upward drags, and cancelled pans cannot accidentally close or change the current item.

Photo slideshow pause is session-scoped state owned by `MediaViewerCoordinator`, separate from video playback state. Pausing cancels the pending photo interval immediately, remains in effect across manual photo/video navigation and system interruptions, and is cleared only when the viewer session ends. Resuming starts a complete new dwell interval only after the current full photo is ready and the app is active.

Photo presentation uses an explicit `loading / ready / failed` state. Slideshow timing starts only after the full photo reports that it is visible. Loading, failure, retry, app interruption, and iPhone zoom inspection all cancel the pending interval; a successful load starts a fresh interval. State callbacks carry the originating media ID, so a late completion from a cancelled previous image cannot accidentally start the timer for the newly selected photo.

Small policy objects live in files named after their responsibility: `ServerAddressNormalizer` validates persisted endpoints, `JellyfinPlaybackURLBuilder` owns same-origin and reverse-proxy playback URL rules, and `MediaPlaybackReportSequencer` owns report ordering. Network clients delegate to these objects instead of accumulating unrelated policy helpers.

Production composition supplies Jellyfin with the real bundle version and a platform-specific device name, so server dashboards can distinguish iPhone, iPad and Apple TV sessions. Settings surfaces the same version/build pair for support. Authenticated artwork is fetched through an ephemeral session with no disk URL cache; decoded images remain in a bounded memory cache that is cleared proactively on system memory warnings.

Both app targets declare a user-facing local-network purpose string. Source homes expose an explicit recheck action in addition to automatic checks, allowing a sleeping NAS to recover without restarting the app or entering a failing library. Image requests fail within their configured timeout instead of waiting indefinitely for connectivity, after which the viewer offers an in-place retry.

Platform entry views remain composition roots only. iOS `RootTabView` wires tabs and dependencies while the media-source home lives under the media feature. Settings UI is divided into overview, service details, and reusable controls. tvOS follows the same page-versus-section separation while retaining its focus-specific controls and theme.

Source-readiness events identify the family-media or Jellyfin source that changed. Each platform tracks which source owns the visible navigation stack and returns to its source home only when that same source changes configuration or loses authentication. A Jellyfin login refresh can no longer discard a retained family-media folder, while an expired Jellyfin session cannot leave Apple TV stranded inside an unusable stale directory. The hidden iOS source-home navigation bar still supplies the title “媒体” as back-button context, avoiding an English system fallback on the first pushed library.

Settings presentation never exposes server enum values as household-facing copy. Shared presentation models translate scan lifecycle states such as `running`, `completed`, and `failed` into consistent Chinese descriptions used by both iOS and tvOS, while detailed counters remain available below for troubleshooting.

Scan and health summaries also hide server job identifiers and omit counters that were not supplied. Visible labels use household terms such as “已检查文件”“内容索引”和“封面生成” instead of raw status values, metadata jargon, or FFmpeg implementation details. Raw scan errors and health-check messages are never rendered because they may contain English implementation text, filesystem paths, SQLite details, or NAS permission output; failed rows instead identify the affected household action and suggest checking storage or directory permissions. Unknown family-media HTTP failures, decoding paths, Jellyfin status codes, and uncommon URL errors follow the same normalization rule. Network failures lead with actions a household user can take—confirming the NAS is awake, the devices share a local network, and local-network permission is enabled—while the sanitized diagnostics screen remains available when deeper support is needed.

The viewer distinguishes a short inactive transition from the app entering the real background. A short system overlay pauses video, releases the media audio session, and reports paused progress without discarding the resolved stream. Entering the background upgrades that suspension: the current position is retained, AVPlayer is cleared, and the Jellyfin session receives one stopped report so HLS transcoding cannot continue unattended. Returning requests a fresh PlaybackInfo URL, seeks near the retained position, and remains paused until the household user explicitly continues. An in-flight playback resolution is cancelled and can be prepared again without autoplay. Photo auto-advance remains suspended until the app becomes active.

Playback started, progress, pause, and stopped reports pass through one sequencer. This preserves lifecycle order during slow network responses and prevents an old stop report from racing behind a new start report. Pending progress reports are coalesced to the newest value, and a stopped report discards stale queued progress because it already carries the final position. The queue therefore stays bounded and Jellyfin can release an active FFmpeg job promptly after the viewer exits, even after a period of poor connectivity.

## API Contract

Current client expects the v1 server contract:

```http
GET /api/v1/browse?kind=...&containerID=...&sort=...&limit=50&cursor=...
POST /api/v1/admin/scan
GET /api/v1/admin/scan/status
POST /api/v1/admin/media/{id}/thumbnail/regenerate
GET /healthz
```

Response shape:

```json
{
  "items": [
    {
      "id": "video-1",
      "name": "birthday.mp4",
      "kind": "video",
      "size": 1024,
      "modified": "2026-05-19T10:00:00Z",
      "url": "http://NAS_LAN_IP:8080/media/original/birthday.mp4",
      "thumbnailURL": "http://NAS_LAN_IP:8080/media/thumbnails/birthday.jpg",
      "mediaPath": "birthday.mp4",
      "thumbnailStatus": "ready"
    }
  ],
  "nextCursor": "",
  "hasMore": false
}
```

`thumbnailURL` can be empty while `thumbnailStatus` is `pending` or `failed`; clients show a placeholder and do not load original media as a thumbnail.

Scan status follows the server client API guide. The client relies on `jobId`, `status`, `startedAt`, `finishedAt`, and `error`; scan counters are displayed when present and treated as optional. Settings triggers a manual scan, polls scan status until a terminal status or timeout, and increments an internal refresh token when a scan completes.

Error responses are decoded from:

```json
{
  "error": "invalid_cursor"
}
```

When list pagination receives `invalid_cursor`, the client restarts that list from the first page.

The shared library store removes duplicate client IDs both within a page and across appended pages while preserving the first-seen order. Both platforms prefetch when one of the final eight visible items appears, hiding most NAS round-trip latency without eagerly loading an entire library. Pagination stops defensively when a server claims more results but omits or repeats its cursor, preventing an endless request loop during a malformed response.

Thumbnail regeneration is a manual detail-screen action for cases where the generated thumbnail is not suitable. The client calls the server with the stable media `id` as a path segment; for videos the request body can include `timeOffsetSeconds` when a later UI exposes custom frame selection. After regeneration succeeds, the current media list refreshes from the first page so the grid can pick up the updated thumbnail status or URL.

## tvOS Behavior

- Home screen has family media, Jellyfin, and settings source entries using the same visual language and source descriptions as iOS.
- Media screens use a grid that supports tvOS focus navigation through native SwiftUI buttons, with explicit focused borders and accessibility labels.
- Top-level Jellyfin containers are labeled as media libraries; containers reached inside a library are labeled as folders on both platforms.
- Initial loading uses skeleton artwork cards; missing or failed artwork has a stable placeholder instead of an indefinite spinner.
- Grid pagination loads the next cursor when the user approaches the end.
- Refresh keeps existing content visible. Refresh and pagination failures have separate messages and retry the correct request.
- Empty API results show a clear illustrated empty state.
- Empty libraries and empty nested folders use distinct household-facing messages and symbols.
- Network or decoding failures show a non-crashing error state with retry.
- Media detail uses a unified full-screen viewer for videos and photos.
- Playback controls support previous, play/pause, next, media information, and thumbnail regeneration only when the source provides that capability.
- Photo playback omits the video-only play control. Pressing Menu while the thumbnail panel is open closes the panel before leaving the viewer.
- Preparing, transcoding, buffering, photo-load failure, and playback failure states provide visible feedback; failed video playback can be retried.
- Autoplay stops after the configured item count and returns to the selected list position.
- Settings uses household-oriented descriptions and visual cards while preserving server URL editing, connection checks, scan triggering, scan status, and playback settings.

## iOS Behavior

- The universal iOS target explicitly supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`); iPad does not have a separate target or duplicate dependency graph.
- Compact width keeps the media and settings tabs, while regular width presents one `NavigationSplitView` sidebar with media home, family media, Jellyfin, and settings destinations. Narrow iPad Split View therefore falls back to the same compact navigation as iPhone.
- Adaptive navigation owns one shared source registry and availability store. Switching sidebar destinations clears only the detail navigation path and active load, while source sessions, connection state, and persisted sort choices remain intact. A width-class change preserves the current top-level source when it can be mapped and safely returns deep folder navigation to that source's entry page.
- `RootNavigationState` is a small value-state machine for tab, sidebar, onboarding, and active-source transitions. `RootTabView` remains the composition and lifecycle boundary, while navigation decisions are deterministic and unit tested without rendering SwiftUI.
- Unavailable family media and signed-out Jellyfin destinations resolve to settings instead of presenting an empty detail column.
- Media screens use one production visual system across source cards, navigation bars, grids, empty states, settings, and the viewer.
- Media grids use two explicit columns on compact-width iPhone and an adaptive 170–260 point card width in regular-width detail columns. Accessibility text increases the regular-width minimum and reduces compact width to one column. Thumbnail overlays cannot contribute their portrait or landscape image's intrinsic size, title rows reserve a consistent line count, and the outer navigation/button frame is clipped to its assigned column. Mixed artwork, missing covers, and short or long titles therefore keep aligned, non-overlapping cards and hit targets.
- Accessibility Dynamic Type increases the grid's minimum card width so long titles remain readable instead of being squeezed into narrow multi-column tiles.
- Grid pagination loads the next cursor when the user approaches the end.
- Nested library and folder navigation uses the same tile sizing and restores the current scroll position when returning from a child screen.
- Initial loading uses skeleton tiles. Pull-to-refresh keeps the existing content visible, presents a compact updating indicator, and replaces the content only after a successful response.
- Pagination failures remain inline with the loaded content and provide a retry action for the same cursor.
- Empty API results show a clear state that distinguishes a media library from a nested folder.
- Network or decoding failures show a non-crashing error state with retry.
- Media detail uses a unified full-screen viewer for videos and photos.
- The iPhone/iPad viewer pages horizontally between photos and videos without dismissing its `fullScreenCover`. The foreground item follows the drag while the adjacent side uses only an existing thumbnail or placeholder; a second original image, AVPlayer, Jellyfin PlaybackInfo request, and playback report are never started speculatively.
- Paging uses distance and predicted-distance thresholds with resisted first/last-item edges. VoiceOver, video scrubbing, settings presentation, and zoomed-photo inspection disable the custom gesture. Reduce Motion keeps the gesture but replaces the full-screen slide with a short fade.
- Video playback distinguishes preparing, buffering, playing, paused, and failed states. Failures provide an explicit retry action, while photo items omit meaningless video controls.
- Playback controls support previous, play/pause, next, media information, and thumbnail regeneration where the active source supports it. On photos, the same central control pauses or resumes slideshow timing without changing the video playback state machine. iPhone/iPad videos start muted and expose a mute-only control beside the timeline; tvOS remains audible by default and relies on the system output volume.
- Autoplay stops after the configured item count and returns to the selected list position.
- Settings uses task-oriented wording and progressive disclosure for technical details while preserving server URL editing, connection checks, scan triggering, scan status, and playback settings.
- Primary media cards, source entries, player actions, and settings controls provide VoiceOver labels and adapt to accessibility Dynamic Type sizes.
- Source and settings content uses a readable maximum width on iPad while media grids continue to expand adaptively.
- Artwork fades, skeleton pulses, focus scaling, and viewer transitions honor the system Reduce Motion preference where applicable.

## First-Run Guidance

Both apps present a short, native first-run guide that introduces the independent family-media and Jellyfin sources. Completion is stored under the stable `ClientExperienceSettings.hasCompletedOnboardingKey` UserDefaults key, so normal upgrades and relaunches do not repeatedly interrupt the user. iOS can continue directly to settings or browse the source home; tvOS explains that the settings entry is where the NAS address is configured. Each settings screen exposes an action to show the guide again without clearing server addresses, Jellyfin credentials, or playback preferences.

The iOS primary onboarding action owns its full rounded visual region as the button label. Its requested destination is applied only from the full-screen cover's dismissal callback, avoiding a tab-selection mutation during the modal dismissal transaction. This makes “开始连接” reliably enter settings while the secondary action continues to the media home.

## Foreground Recovery

The source home and every visible media library observe the platform scene phase. Returning after a meaningful period away rechecks source availability and rebuilds the media pagination window that was already loaded while retaining visible content during the request. Retained parent folders do not react while a deeper navigation destination or the viewer is covering them; a missed refresh generation is consumed when that folder becomes visible again. This prevents a deeply nested navigation stack from issuing one NAS request per retained level after foreground recovery. The current iOS scroll target or tvOS focused item is supplied as a refresh anchor. If newly inserted media moved that anchor beyond the previous page boundary, Core inspects at most two additional pages to recover it without allowing an unbounded NAS request loop. Source checks use a 30-second minimum interval and library refreshes use 60 seconds, preventing short notification, Control Center, or app-switch interruptions from repeatedly hitting the NAS. Manual refresh always bypasses this recency policy.

Overlapping source checks are coalesced while a visible screen is active: one queued refresh is drained by the current task after its request finishes. Initial appearance, pull-to-refresh, manual, source-change, and foreground checks are all owned by a view task controller. Its awaitable path lets SwiftUI wait for refresh completion without giving up explicit cancellation ownership; a newer check replaces an older one, and leaving the screen or moving the app out of the active state cancels the work. Core does not create an unstructured replacement request after cancellation. This keeps NAS traffic bound to the visible UI lifecycle during long-running installations.

`MediaSourceRefreshCenter` is separate from the media-library content refresh token. Saving a changed family-media or Jellyfin address, completing a connection check, logging in, logging out, or detecting that a Jellyfin session changed publishes a source refresh. iOS and tvOS then update their source cards immediately, so returning from settings does not require a manual recheck or wait for a foreground interval. On iOS, a source identity change also resets stale nested navigation before the refreshed source is opened.

When a persisted Jellyfin session exists, its foreground health check validates both public server information and the current authenticated user. A 401 clears only the stale Jellyfin token and changes the source to the login-required state; it does not affect the family-media source. The full-screen viewer handles scene interruptions independently: video pauses and does not resume unexpectedly, an in-flight playback-resolution request is cancelled and may be prepared again in a paused state, and photo auto-advance remains suspended while the app is inactive.

The Jellyfin API client emits a source-readiness refresh only when a 401 actually clears the token used by that request. A late 401 from an older request cannot clear a newer login or publish a false invalidation. Playback therefore updates the source home and settings state immediately after an expired token instead of waiting for the next foreground health interval.

If that foreground check invalidates a Jellyfin session, `MediaSourceAvailabilityStore` publishes one source-state change for the ready-to-authentication-required transition. `JellyfinSettingsStore` observes the same refresh center and reloads its session snapshot without publishing recursively. Consequently, a settings screen that has remained mounted for hours cannot keep showing an obsolete “已登录” badge after Keychain has been cleared; iOS and tvOS converge on the same login-required state without recreating their view hierarchy.

## Network Request Lifecycle

Production family-media and Jellyfin API traffic shares an ephemeral `MediaNetworkSession` with no URL cache, a 15-second request timeout, a 60-second resource ceiling, and a six-connection-per-host limit. Authentication headers and JSON responses therefore do not enter the persistent system URL cache, while a sleeping or unreachable NAS still produces a bounded, user-facing timeout.

Both configuration stores maintain an in-memory address revision. Every family-media response and Jellyfin response is accepted only if the configured address still has the revision used when that request started. A late response from a previous NAS is treated as cancellation instead of replacing current media or health state. Jellyfin login repeats the revision check immediately before and after Keychain persistence, preventing an old server token from reappearing after the address was changed or the request was cancelled.

User-initiated work on media, settings, and diagnostics screens is owned by a shared `ViewTaskController`. Starting a replacement action cancels the previous one, and leaving the owning screen cancels outstanding connection checks, scan polling, refreshes, and retries. Cancellation is silent in shared stores: it restores retained list content or an idle state rather than presenting a false network failure.

Grid pagination uses SwiftUI tasks keyed by whether that exact library is visible, active, and uncovered by the full-screen viewer. Moving the app inactive, opening a child folder, or presenting playback changes the key and cancels an in-flight prefetch. `MediaLibraryStore` keeps the loaded page window and cursor on cancellation, clears its loading indicator, and can retry the same cursor when the view becomes eligible again. Long Jellyfin folders therefore do not continue downloading pages behind playback or while the device is locked.

Foreground refresh throttling is based on the most recent request that actually completed, not the time a request began. If iOS or tvOS moves inactive while a source check or media refresh is running, the view cancels that work; returning to the foreground can retry immediately instead of leaving a cancelled first load on a skeleton screen for the normal throttle interval. Completed success and failure responses remain throttled so a sleeping NAS is not hammered.

Both apps also share a `NetworkRecoveryObserver` backed by `NWPathMonitor`. The first system path callback establishes a baseline and does not cause a duplicate cold-start request. Later Wi-Fi, Ethernet, cellular, constrained-network, and connectivity changes are debounced before requesting one source recheck and publishing one media-library refresh generation. The currently visible folder can therefore recover automatically when the NAS becomes reachable again; hidden parent folders and a list covered by the viewer defer that generation until they are visible. A change received while the app is inactive remains pending and is consumed once on the next foreground transition, bypassing the normal recency throttles so returning to the home network can recover immediately without repeatedly probing the NAS. On tvOS, the retained but hidden home screen forwards the library refresh without running its own health checks, then refreshes source cards when the user returns home.

Source-home appearance uses the same completion-based recency policy. The first cold appearance checks both sources, but returning from a media library or settings within thirty seconds reuses the latest availability instead of issuing another pair of health requests. Manual refresh, saved configuration changes, authentication changes, and a consumed network-path event remain explicit force-refresh paths.

`MediaSourceAvailabilityStore` derives its first published state synchronously from each context's readiness before any network task can start. Family media and an authenticated Jellyfin session begin as checking and remain browsable while health is resolved; a signed-out Jellyfin context begins as authentication-required on the very first frame. This prevents a fast tap during cold launch from entering a protected library before the asynchronous source check has had a chance to update the card.

The family-media-only cover regeneration action follows the same ownership rule. Closing either viewer cancels an in-flight request before it can refresh a list that is no longer visible, and cancellation does not appear as a false failure. The UI calls this operation “重新生成封面” and never displays the server's thumbnail-state enum.

Family-media scan polling retains each newly fetched status so counters continue updating while the settings screen is visible. Leaving the screen or backgrounding the app cancels only client polling; the NAS scan continues independently. Entering the family-media settings page first asks the NAS for its current scan status, so a newly recreated client can discover and resume a server-side job even when its previous in-memory state was lost. Reopening settings or returning to the foreground follows the same path. A completed job publishes the media-library refresh token exactly once per settings-store lifetime whether completion was observed by the original polling loop, a resumed loop, a recreated client, or a later manual status check, so newly indexed content becomes visible without requiring another scan. While a connection check or scan operation is active, conflicting settings actions remain disabled instead of silently cancelling and replacing each other.

## Playback Resource Lifecycle

`MediaPlaybackController` owns AVPlayer observation and a platform media audio session. iOS and tvOS use the `.playback` category with movie mode, so video audio behaves like media rather than notification audio. Switching directly between autoplaying videos keeps the audio session active; failure, viewer exit, a switch to photos, or moving the app into the background releases it and notifies other audio apps. A real background transition also releases AVPlayer and ends the server play session while retaining a bounded resume position. Rebuilding that video with a fresh playback resolution in a paused state does not reactivate or steal the audio session. If the viewer remains open, the session is activated again only when the household user manually continues playback.

All AVPlayer end, failure, status, time-control, timeline, buffer, and reporting callbacks capture their originating player weakly and verify that it is still the controller's current player before changing state. Removing observers cannot retract a callback already queued on the main actor, so this identity gate prevents a late failure or end event from an old video from failing the replacement player or advancing the sequence twice during rapid navigation. Failure-notification closures also capture the controller weakly at the outer notification boundary, preventing the notification token from forming a retain cycle with its owner. The controller has an actor-isolated destruction fallback that removes notification, KVO, and periodic-time observers, pauses and releases the player, and deactivates the media audio session. Normal viewer dismissal still performs the same cleanup immediately; the destruction path protects against SwiftUI view replacement or an unexpected ownership teardown that bypasses the normal callback.

Periodic Jellyfin progress reporting derives its paused flag from the current AVPlayer state instead of assuming every timer callback means active playback. A periodic callback delivered around a pause or seek therefore cannot make the Jellyfin dashboard incorrectly show the session as playing again.

The shared playback layer also observes system audio interruptions and route loss. A call, alarm, or removal of the active audio output pauses the current video through the same session state machine used by the UI, including a paused Jellyfin progress report when playback had started. Playback never resumes automatically after the system event; the household user explicitly continues when ready.

Once PlaybackInfo has produced a resolution, `MediaPlaybackSessionController` treats the Jellyfin play session as an active resource even before AVPlayer reaches ready-to-play. Exiting, failing, or switching during initial HLS buffering therefore queues exactly one stopped report, which allows Jellyfin to terminate an early FFmpeg job instead of waiting for its server timeout. AVPlayer observers, time observers, and the player instance are cleared immediately on failure while the user-facing failed state remains available for retry.

Playback lifecycle reports are serialized so `Playing` is observed before later progress or stop events, but a stop event has higher release priority than progress. It removes queued progress reports and cancels an in-flight progress request before sending `Playing/Stopped`. Since the HTTP request inherits Swift task cancellation, leaving the viewer on a slow or broken network no longer waits for the progress timeout before Jellyfin can release its FFmpeg process.

`MediaViewerWakePolicy` keeps the system idle timer disabled only while an active viewer needs uninterrupted presentation: loading or visible photos, video preparation, buffering, and playback. A failed photo, paused or failed video, an inactive/background scene, and viewer dismissal release the shared `PlaybackIdleTimerController`, restoring the exact idle-timer value that existed before the viewer acquired it. The controller also restores that value from its actor-isolated destruction fallback, protecting against a SwiftUI hierarchy replacement that bypasses the normal disappearance callback. This prevents iPhone auto-lock and the Apple TV screen saver from interrupting a slideshow or a long buffering start without keeping the device awake on an unattended failure screen.

Shared delayed actions used by slideshow timing, viewer chrome, focus restoration, and buffering detection identify each scheduled task. Completion clears the stored task only when it is still current, so an action that schedules its replacement cannot be erased by the old task's cleanup. Cancelled and completed tasks release their closures immediately instead of retaining stale view state for the lifetime of a long-running screen.

Remote image loaders also identify every view request independently from the shared download key. A late success or failure may update the visible phase only when its request identity is still current. This protects recycled SwiftUI grid cells from briefly presenting the previous media item's artwork when rapid scrolling overlaps cancellation and completion.

Persisted Jellyfin sessions are bound to the normalized server URL separately from the Keychain credential. A normal upgrade from an older client migrates an unbound session only when the installation's stable Jellyfin device ID is still present. If UserDefaults were removed while a Keychain item survived, the missing device identity identifies that credential as orphaned and the client clears it instead of sending an old server token to the bundled fallback address. Changing the server URL or receiving an authenticated 401 clears both the Keychain session and its server binding.

iPhone and iPad video rendering uses the shared `PlayerSurfaceView`, a thin `AVPlayerLayer`-backed surface with no built-in transport controls. The touch viewer therefore presents exactly one custom control system for paging, mute, timeline seeking and status. Dismantling the surface clears its player reference immediately.

tvOS video presentation is intentionally separate. A stable `AVPlayerViewController` receives the `AVPlayer` owned by `MediaPlaybackSessionController`, so the system owns Siri Remote scrubbing, play/pause, transport-bar visibility, AirPlay and playback settings while Core continues to own resolution, cancellation and Jellyfin reporting. Video-to-video navigation replaces only the player and metadata inside that controller; it does not dismiss the full-screen viewer. Previous/next and family-media cover regeneration are AVKit transport actions, and shared media information is exposed as an AVKit info tab. Photos keep the custom tvOS chrome because slideshow navigation and photo inspection are not video transport concerns.

The iPhone viewer treats navigation and transport controls as transient chrome. A single tap restores or dismisses them, and they auto-hide after four seconds only while a video is actively playing or a photo has loaded successfully. Preparing, buffering, paused, failed, photo-loading, VoiceOver, scrubbing, and settings states keep the controls visible. Compact-height landscape uses reduced control spacing, padding, and play-button size while preserving the same actions and safe-area margins. Single-tap recognition waits for the photo double-tap zoom gesture to fail, so zooming and chrome control do not compete; inspecting a zoomed photo also suspends slideshow advancement. A viewport-size change resets the UIKit zoom surface and explicitly clears the shared inspection state, so rotating a zoomed photo cannot leave slideshow advancement permanently suspended.

For tvOS video, AVKit handles the physical Play/Pause button, directional input and touch-surface scrubbing. Core observes the resulting AVPlayer activity and time-jump events, deduplicates pause/resume reports and immediately reports a completed system seek to Jellyfin. The custom remote-capture surface is now photo-only: with photo controls hidden, Left/Right moves to the previous or next item and Select reveals the photo controls.

Both platforms feed the same context into `ViewerChromeController`; `ViewerChromePolicy` only answers whether that context permits automatic hiding. The controller cancels a previous item's timer when media changes, keeps controls pinned after pause or a system audio interruption, and resumes automatic hiding only after playback is active. VoiceOver and the settings panel always pin controls; photo controls hide only after the image is actually ready.

## Image Memory and Cache Lifecycle

`CachedRemoteImage` uses one ephemeral URL session with no URL cache, a six-connection-per-host limit, ImageIO downsampling, and a cost-limited in-memory `NSCache`. Memory warnings immediately clear decoded cache entries. Grid artwork remains data-backed because both servers return bounded thumbnails; full photo-viewer requests use `URLSession.download` and downsample directly from the temporary file, avoiding an additional full-size `Data` allocation for large phone originals. Temporary files are removed immediately after decoding. `MediaSourceContext` optionally supplies a resource-request authorizer: Jellyfin artwork and photos use the normal MediaBrowser authorization header instead of embedding `api_key` in catalog URLs, while the unauthenticated family source keeps plain requests. A protected-image 401 is returned to that authorizer, which clears the session only if the failed request still carries the current token and publishes a Jellyfin-only source refresh. A late image response from an older login can therefore never invalidate its replacement session.

The in-memory key includes URL, target pixel size, a caller-provided cache version, and a non-secret session partition. A logout or replacement Jellyfin login therefore cannot reuse protected images decoded for the previous session, and the raw token never enters the cache key. Thumbnail regeneration increments the version only for the affected media ID on the current library screen. The new thumbnail therefore misses the old decoded entry exactly once, while unrelated visible artwork stays cached. Each underlying transfer also has a unique request identity. If the final waiter cancels and the same image is immediately requested again, the late completion from the cancelled transfer cannot remove or fail the replacement request. iOS image-pipeline tests use a stubbed URL protocol to prove authorization-header delivery, session isolation, same-version reuse, versioned invalidation, file-backed photo loading, request coalescing, waiter cancellation, and immediate retry isolation.

The visible image phase is also keyed to the current view request identity. When a lazy grid cell is reused for a different URL or a regenerated-cover version, its previous image or failure state becomes ineligible in the same render pass, before the replacement task starts. This avoids a one-frame wrong cover while rapidly scrolling large libraries.

## User-Safe Diagnostics

Settings on both platforms includes a native help and diagnostics destination. It can check both configured sources and formats a shared `ClientDiagnosticsReport` containing the app version, platform version, sanitized server addresses, connection state, and Jellyfin login state. iOS can copy the report; tvOS uses a large readable layout intended for photographing from the television.

`ClientEventLog` adds a non-persistent, 100-entry ring buffer and Apple Unified Logging categories for network, browse and playback boundaries. Records accept only fixed event codes, operation UUIDs, source enum, playback method, outcome and HTTP status class. They cannot accept URLs, tokens, user names, device IDs, media IDs, file names, paths or server error text. Diagnostics includes only the newest 30 structured events; progress ticks are intentionally excluded.

The report formatter removes URL user info, passwords, query parameters, and fragments before producing text. It never receives or emits the Jellyfin token, username, media filenames, or persistent device ID. `SettingsStore` and `JellyfinSettingsStore` own explicit connection states consumed by both apps, so changing an address or receiving a newer failure cannot leave stale successful diagnostics on screen.

Jellyfin sessions are stored as a generic-password Keychain item using `AfterFirstUnlockThisDeviceOnly`. Session replacement uses `SecItemUpdate` and falls back to add only when no item exists, so a failed replacement never deletes the last valid login first. Reads, saves, unconditional logout, and conditional invalidation share one store lock. A 401 clears the Keychain item only when its complete captured session still matches the stored value; comparing and deleting happen inside the same critical section, so a concurrent successful login cannot be removed between an API-level check and a later delete. Password text is never persisted and is cleared after login, logout, leaving the Jellyfin form, or moving the app out of the active foreground; the non-sensitive username and server address remain available for another attempt.

## Local Network Configuration

Both Apple targets bundle the same `PrivacyInfo.xcprivacy`. It declares no tracking domains or developer data collection and records `CA92.1` for UserDefaults that are private to each app. The settings stored there are limited to server addresses, playback preferences, onboarding state, and a stable Jellyfin device identity; credentials remain in Keychain. Keeping the manifest in the shared Apple UI resource directory ensures iOS and tvOS cannot drift while XcodeGen includes the same declaration in both app bundles.

Each app target uses a persisted server URL. The default value is read from `FAMILY_MEDIA_SERVER_BASE_URL` in its own `Info.plist`.

All bundled and persisted addresses pass through `ServerAddressNormalizer` before entering a request builder. Safe legacy differences such as host casing, default ports, whitespace, or a trailing slash are migrated in place. Relative URLs, unsupported schemes, credentials, queries, fragments, and otherwise corrupt values are discarded in favor of the bundled fallback, so a damaged preference or Info.plist edit cannot crash startup or silently redirect credentials.

Default value:

```text
http://NAS_LAN_IP:8080
```

Update this value to match the server address before running on Apple TV, iPhone, or Simulator.

`NSAllowsLocalNetworking` is enabled for local HTTP access.

## iOS Debug Demo Mode

Debug builds expose an `演示内容` switch at the top of iOS settings. It replaces only the active browsing registry with local demo catalogs; persisted server URLs, Jellyfin tokens, device identity, and production services remain untouched. This local data switch is the only Debug-only part of the polish pass; adaptive layout, loading and refresh behavior, nested navigation, player states, accessibility, and visual consistency are production features included in Release builds.

Changing the demo mode or scenario clears the media tab's bound `NavigationPath` without replacing its `NavigationStack`. Keeping the tab navigation host stable avoids stale navigation and hit-testing state when the setting changes while the settings tab is selected.

Available scenarios are:

- `正常内容`: family photos/videos, Jellyfin libraries, nested folders, missing artwork, long titles, and a paginated 58-item folder.
- `空媒体库`: validates empty-state presentation.
- `连接失败`: validates error mapping and retry presentation.

Demo artwork is rendered locally by SwiftUI. Demo videos intentionally resolve to a clear playback failure so the player error and retry flow can be tested without bundling media files. The switch and demo catalog types are compiled only under `#if DEBUG` and do not appear in Release builds.

## UI Smoke Tests

The generated project includes `FamilyMediaiOSUITests` and `FamilyMediaTVUITests`. Both targets launch Debug builds with the private `--ui-testing` argument, which makes onboarding deterministic without modifying normal app launches. The local demo catalog is shared by both app targets; iOS enables it through `--ui-testing-demo`, while the tvOS test composition injects it automatically. Source navigation, nested media loading, viewer presentation, and remote navigation therefore run without a NAS.

Stable accessibility identifiers cover the two iOS source cards, family categories, media tiles, viewer dismissal, and the tvOS home cards, categories, media tiles, and viewer controls. The iOS suite opens a real demo media tile, presents the full-screen viewer, dismisses it, and proves the originating item remains available. tvOS tests interact through `XCUIRemote` rather than touch APIs; one test enters a demo library, opens the viewer, navigates to the next item while controls are hidden, reveals the controls, and exits. The tvOS home explicitly restores default focus to Family Media after launch and after onboarding dismissal.

Both suites also have a Debug-only signed-out Jellyfin launch scenario. It injects an `.authenticationRequired` source before the first frame and immediately activates the Jellyfin card, proving that cold-start navigation opens settings instead of an empty library. The displayed availability and destination are derived from the same test context, so the gate also catches UI state and routing drift.

All UI-test launch handling is guarded by `#if DEBUG`. Release builds ignore these arguments and contain neither the demo catalog nor the demo settings controls.

## Project Generation

This repository keeps app project configuration in `project.yml`. After installing Xcode and XcodeGen:

```bash
xcodegen generate
open FamilyMediaClient.xcodeproj
```

Core package tests can run without the generated Xcode project:

```bash
swift test
```
