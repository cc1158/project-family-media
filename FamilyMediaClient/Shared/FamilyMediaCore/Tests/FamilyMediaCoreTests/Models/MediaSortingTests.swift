import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaSortingTests {
    @Test func profilesExposeSourceSpecificRulesAndScopes() {
        #expect(MediaSortingProfile.familyMedia.defaultOption == .capturedNewest)
        #expect(MediaSortingProfile.familyMedia.options == [
            .capturedNewest,
            .capturedOldest,
            .nameAscending,
            .nameDescending,
            .dateAddedNewest
        ])
        #expect(MediaSortingProfile.familyMedia.isAvailable(containerID: nil))

        #expect(MediaSortingProfile.jellyfin.defaultOption == .nameAscending)
        #expect(!MediaSortingProfile.jellyfin.isAvailable(containerID: nil))
        #expect(MediaSortingProfile.jellyfin.isAvailable(containerID: "library-1"))
        #expect(!MediaSortingProfile.jellyfin.isAvailable(containerID: "playlist:list-1"))
    }

    @Test func preferencesAreIsolatedBySourceAndFilterAndRejectUnsupportedValues() {
        let defaults = isolatedDefaults()
        let preferences = MediaSortPreferenceStore(defaults: defaults)

        preferences.save(.nameDescending, sourceID: .familyMedia, filter: .videos)
        preferences.save(.dateAddedOldest, sourceID: .jellyfin, filter: .videos)

        #expect(preferences.selectedSort(
            sourceID: .familyMedia,
            filter: .videos,
            profile: .familyMedia
        ) == .nameDescending)
        #expect(preferences.selectedSort(
            sourceID: .familyMedia,
            filter: .photos,
            profile: .familyMedia
        ) == .capturedNewest)
        #expect(preferences.selectedSort(
            sourceID: .jellyfin,
            filter: .videos,
            profile: .jellyfin
        ) == .dateAddedOldest)

        preferences.save(.capturedOldest, sourceID: .jellyfin, filter: .all)
        #expect(preferences.selectedSort(
            sourceID: .jellyfin,
            filter: .all,
            profile: .jellyfin
        ) == .nameAscending)
    }

    @Test func pageRequestEncodesSortOnlyWhenSpecified() {
        let sorted = MediaPageRequest(limit: 20, cursor: "next", sort: .nameDescending)
        #expect(sorted.queryItems.contains(URLQueryItem(name: "sort", value: "name_desc")))

        let legacy = MediaPageRequest(limit: 20)
        #expect(!legacy.queryItems.contains { $0.name == "sort" })
    }

    @Test func sortPresentationUsesTheExpectedDirectionIndicator() {
        #expect(MediaSortOption.capturedNewest.directionSystemImage == "arrow.down")
        #expect(MediaSortOption.capturedOldest.directionSystemImage == "arrow.up")
        #expect(MediaSortOption.nameAscending.directionSystemImage == "arrow.up")
        #expect(MediaSortOption.nameDescending.directionSystemImage == "arrow.down")
        #expect(MediaSortOption.dateAddedNewest.directionSystemImage == "arrow.down")
        #expect(MediaSortOption.dateAddedOldest.directionSystemImage == "arrow.up")
    }
}
