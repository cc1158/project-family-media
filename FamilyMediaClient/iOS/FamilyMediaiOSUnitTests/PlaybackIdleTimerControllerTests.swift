import XCTest
@testable import FamilyMediaiOS

@MainActor
final class PlaybackIdleTimerControllerTests: XCTestCase {
    func testReleaseRestoresValueThatExistedBeforePlayback() {
        let state = IdleTimerState(value: false)
        let controller = makeController(state: state)

        controller.setPlaybackActive(true)
        XCTAssertTrue(state.value)

        controller.setPlaybackActive(false)
        XCTAssertFalse(state.value)
    }

    func testDeinitRestoresIdleTimerAfterUnexpectedViewerTeardown() {
        let state = IdleTimerState(value: false)
        var controller: PlaybackIdleTimerController? = makeController(state: state)

        controller?.setPlaybackActive(true)
        XCTAssertTrue(state.value)
        controller = nil

        XCTAssertFalse(state.value)
    }

    private func makeController(
        state: IdleTimerState
    ) -> PlaybackIdleTimerController {
        PlaybackIdleTimerController(
            readValue: { state.value },
            writeValue: { state.value = $0 }
        )
    }
}

@MainActor
private final class IdleTimerState {
    var value: Bool

    init(value: Bool) {
        self.value = value
    }
}
