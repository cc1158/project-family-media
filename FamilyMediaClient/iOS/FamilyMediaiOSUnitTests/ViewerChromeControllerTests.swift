import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

@MainActor
final class ViewerChromeControllerTests: XCTestCase {
    func testAutomaticPhotoTransitionStaysHiddenWhenPhotoBecomesReady() {
        let controller = ViewerChromeController(scheduler: ManualChromeScheduler())
        controller.start(context: context(itemID: "first", photoLoadState: .ready))

        controller.itemDidChange(
            event: navigationEvent(itemID: "second", origin: .automatic),
            context: context(itemID: "second")
        )
        XCTAssertEqual(controller.state, .automaticTransition)

        controller.update(context: context(itemID: "second", photoLoadState: .ready))
        XCTAssertEqual(controller.state, .hidden)
    }

    func testAutomaticVideoPreparingBufferingAndPlayingNeverShowsChrome() {
        let controller = ViewerChromeController(scheduler: ManualChromeScheduler())
        controller.start(context: context(itemID: "first", photoLoadState: .ready))
        controller.itemDidChange(
            event: navigationEvent(itemID: "video", origin: .automatic),
            context: context(itemID: "video", kind: .video, playbackState: .preparing)
        )

        controller.update(
            context: context(itemID: "video", kind: .video, playbackState: .buffering(.transcode))
        )
        XCTAssertEqual(controller.state, .automaticTransition)

        controller.update(
            context: context(itemID: "video", kind: .video, playbackState: .playing(.transcode))
        )
        XCTAssertEqual(controller.state, .hidden)
    }

    func testFailureAndBlockingInteractionsKeepChromeVisible() {
        let controller = ViewerChromeController(scheduler: ManualChromeScheduler())
        controller.start(context: context(itemID: "photo", photoLoadState: .ready))
        controller.userDidHide()

        controller.update(context: context(itemID: "photo", photoLoadState: .failed))
        XCTAssertEqual(controller.state, .persistent)

        controller.update(
            context: context(itemID: "photo", isOverlayPresented: true, photoLoadState: .ready)
        )
        XCTAssertEqual(controller.state, .persistent)
    }

    func testUserCanRevealChromeDuringAutomaticTransition() {
        let controller = ViewerChromeController(scheduler: ManualChromeScheduler())
        controller.start(context: context(itemID: "first", photoLoadState: .ready))
        let second = context(itemID: "second")
        controller.itemDidChange(
            event: navigationEvent(itemID: "second", origin: .automatic),
            context: second
        )

        controller.userDidInteract(context: second, autoHide: false)
        controller.update(context: context(itemID: "second", photoLoadState: .ready))

        XCTAssertEqual(controller.state, .visible)
        XCTAssertTrue(controller.isVisible)
    }

    func testManualNavigationShowsChromeAndSchedulesAutoHideWhenReady() {
        let scheduler = ManualChromeScheduler()
        let controller = ViewerChromeController(scheduler: scheduler)
        controller.start(context: context(itemID: "first", photoLoadState: .ready))

        controller.itemDidChange(
            event: navigationEvent(itemID: "second", origin: .manual),
            context: context(itemID: "second", photoLoadState: .ready)
        )
        XCTAssertEqual(controller.state, .visible)

        scheduler.fireLatest()
        XCTAssertEqual(controller.state, .hidden)
    }

    func testLateMediaEventAndOldTimerCannotChangeCurrentState() {
        let scheduler = ManualChromeScheduler()
        let controller = ViewerChromeController(scheduler: scheduler)
        controller.start(context: context(itemID: "first", photoLoadState: .ready))
        let oldTimerIndex = scheduler.latestActionIndex

        controller.itemDidChange(
            event: navigationEvent(itemID: "second", origin: .automatic),
            context: context(itemID: "second")
        )
        controller.update(context: context(itemID: "first", photoLoadState: .failed))
        scheduler.fire(at: oldTimerIndex)

        XCTAssertEqual(controller.state, .automaticTransition)
    }

    private func navigationEvent(
        itemID: String,
        origin: MediaViewerNavigationOrigin
    ) -> MediaViewerNavigationEvent {
        MediaViewerNavigationEvent(
            sequence: 1,
            itemID: itemID,
            index: 1,
            origin: origin
        )
    }

    private func context(
        itemID: String,
        kind: MediaKind = .photo,
        playbackState: MediaPlaybackState = .idle,
        isOverlayPresented: Bool = false,
        photoLoadState: MediaPhotoLoadState = .loading
    ) -> ViewerChromeContext {
        ViewerChromeContext(
            itemID: itemID,
            mediaKind: kind,
            playbackState: playbackState,
            isSceneActive: true,
            isVoiceOverEnabled: false,
            isScrubbing: false,
            isOverlayPresented: isOverlayPresented,
            isPhotoInspectionActive: false,
            photoLoadState: photoLoadState,
            isPhotoAutoAdvancePaused: false
        )
    }
}

@MainActor
private final class ManualChromeScheduler: DelayedActionScheduling {
    private(set) var actions: [(@MainActor () -> Void)?] = []

    var latestActionIndex: Int { actions.index(before: actions.endIndex) }

    func schedule(afterSeconds: Int, action: @escaping @MainActor () -> Void) {
        actions.append(action)
    }

    func cancel() {}

    func fireLatest() {
        fire(at: latestActionIndex)
    }

    func fire(at index: Int) {
        guard actions.indices.contains(index), let action = actions[index] else { return }
        actions[index] = nil
        action()
    }
}
