import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

final class RootNavigationStateTests: XCTestCase {
    func testSidebarSourceSelectionTracksTheActiveSource() {
        var state = RootNavigationState()

        state.selectSidebarDestination(.jellyfin) { _ in true }

        XCTAssertEqual(state.selectedSidebarDestination, .jellyfin)
        XCTAssertEqual(state.activeMediaSourceID, .jellyfin)
    }

    func testUnavailableSourceSelectionRoutesToSettings() {
        var state = RootNavigationState()

        state.selectSidebarDestination(.familyMedia) { _ in false }

        XCTAssertEqual(state.selectedSidebarDestination, .settings)
        XCTAssertNil(state.activeMediaSourceID)
    }

    func testResettingIPadNavigationReturnsToMediaHome() {
        var state = RootNavigationState()
        state.selectedSidebarDestination = .jellyfin
        state.activeMediaSourceID = .jellyfin

        state.resetMediaNavigation(for: .iPadSplit)

        XCTAssertEqual(state.selectedSidebarDestination, .mediaHome)
        XCTAssertNil(state.activeMediaSourceID)
    }

    func testResettingPhoneNavigationDoesNotMutateSidebarSelection() {
        var state = RootNavigationState()
        state.selectedSidebarDestination = .jellyfin
        state.activeMediaSourceID = .jellyfin

        state.resetMediaNavigation(for: .phoneTabs)

        XCTAssertEqual(state.selectedSidebarDestination, .jellyfin)
        XCTAssertNil(state.activeMediaSourceID)
    }

    func testOnboardingDestinationIsAppliedAfterDismissal() {
        var state = RootNavigationState()

        state.prepareOnboardingDestination(openSettings: true)
        XCTAssertEqual(state.pendingOnboardingTab, .settings)

        state.applyOnboardingDestination()
        XCTAssertEqual(state.selectedTab, .settings)
        XCTAssertEqual(state.selectedSidebarDestination, .settings)
        XCTAssertNil(state.pendingOnboardingTab)
    }
}
