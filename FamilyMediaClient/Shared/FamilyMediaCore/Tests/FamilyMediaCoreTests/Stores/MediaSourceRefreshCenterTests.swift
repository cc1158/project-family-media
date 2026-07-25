import Testing
@testable import FamilyMediaCore

struct MediaSourceRefreshCenterTests {
    @Test @MainActor func sourceSpecificRefreshOnlyAffectsMatchingNavigation() {
        let center = MediaSourceRefreshCenter()

        center.publishRefresh(for: .jellyfin)

        #expect(center.generation == 1)
        #expect(center.affectedSourceID?.rawValue == MediaSourceID.jellyfin.rawValue)
        #expect(center.affectsNavigation(for: .jellyfin))
        #expect(!center.affectsNavigation(for: .familyMedia))
        #expect(!center.affectsNavigation(for: nil))
    }

    @Test @MainActor func unspecifiedRefreshSafelyAffectsEveryNavigation() {
        let center = MediaSourceRefreshCenter()

        center.publishRefresh()

        #expect(center.generation == 1)
        #expect(center.affectedSourceID == nil)
        #expect(center.affectsNavigation(for: .familyMedia))
        #expect(center.affectsNavigation(for: .jellyfin))
        #expect(center.affectsNavigation(for: nil))
    }
}
