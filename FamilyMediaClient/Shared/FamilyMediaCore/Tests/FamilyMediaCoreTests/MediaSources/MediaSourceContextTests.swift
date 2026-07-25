import Foundation
import Testing
@testable import FamilyMediaCore

struct MediaSourceContextTests {
    @Test func registryKeepsSourceCapabilitiesIsolated() {
        let familyService = FakeMediaService()
        let jellyfinCatalog = FakeMediaService()
        let reporter = RecordingPlaybackReporter()
        let family = MediaSourceContext(
            id: .familyMedia,
            catalog: familyService,
            playbackResolver: DirectMediaPlaybackResolver(),
            admin: familyService
        )
        let jellyfin = MediaSourceContext(
            id: .jellyfin,
            catalog: jellyfinCatalog,
            playbackResolver: DirectMediaPlaybackResolver(),
            playbackReporter: reporter,
            catalogStructure: .libraryRoot
        )
        let registry = MediaSourceRegistry(familyMedia: family, jellyfin: jellyfin)

        #expect(registry.familyMedia.id == MediaSourceID.familyMedia)
        #expect(registry.familyMedia.admin != nil)
        #expect(registry.familyMedia.playbackReporter == nil)
        #expect(registry.familyMedia.resourceRequestAuthorizer == nil)
        #expect(registry.familyMedia.catalogStructure == .folderTree)
        #expect(registry.jellyfin.id == MediaSourceID.jellyfin)
        #expect(registry.jellyfin.admin == nil)
        #expect(registry.jellyfin.playbackReporter != nil)
        #expect(registry.jellyfin.catalogStructure == .libraryRoot)
    }

    @Test func presentationHidesTranscodeMessageAfterPlaybackStarts() {
        #expect(MediaPlaybackPresentation(state: .buffering(.transcode)).title == "Jellyfin 正在转码")
        #expect(MediaPlaybackPresentation(state: .buffering(.transcode)).isVisible)
        #expect(!MediaPlaybackPresentation(state: .playing(.transcode)).isVisible)
    }
}

private actor RecordingPlaybackReporter: MediaPlaybackReporting {
    func reportPlaybackStarted(item: MediaItem, resolution: MediaPlaybackResolution) async {}
    func reportPlaybackProgress(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64,
        isPaused: Bool
    ) async {}
    func reportPlaybackStopped(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64
    ) async {}
}
