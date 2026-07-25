import XCTest
@testable import FamilyMediaiOS

final class ViewerDismissGestureTests: XCTestCase {
    func testDownwardDistanceOrProjectionCommitsDismissal() {
        XCTAssertTrue(
            shouldDismiss(translation: CGSize(width: 10, height: 180))
        )
        XCTAssertTrue(
            shouldDismiss(
                translation: CGSize(width: 4, height: 40),
                projected: CGSize(width: 8, height: 300)
            )
        )
    }

    func testUpwardHorizontalAndShortDragsDoNotDismiss() {
        XCTAssertFalse(shouldDismiss(translation: CGSize(width: 0, height: -240)))
        XCTAssertFalse(shouldDismiss(translation: CGSize(width: 220, height: 80)))
        XCTAssertFalse(shouldDismiss(translation: CGSize(width: 4, height: 60)))
    }

    func testPresentationFollowsDragAndResetsCleanly() {
        var state = ViewerDismissPresentationState()
        state.update(
            translation: CGSize(width: 4, height: 200),
            viewportHeight: 800
        )

        XCTAssertTrue(state.isInteracting)
        XCTAssertEqual(state.offset, 200)
        XCTAssertLessThan(state.scale, 1)
        XCTAssertLessThan(state.backgroundOpacity, 1)

        state.reset()
        XCTAssertEqual(state, ViewerDismissPresentationState())
    }

    func testReduceMotionDismissUsesFadeWithoutMovingContent() {
        var state = ViewerDismissPresentationState()
        state.beginDismiss(viewportHeight: 800, reduceMotion: true)

        XCTAssertTrue(state.isTransitioning)
        XCTAssertEqual(state.offset, 0)
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.contentOpacity, 0)
        XCTAssertEqual(state.backgroundOpacity, 0)
    }

    func testPhotoDismissStartsOnlyAtOriginalZoomForDownwardPan() {
        XCTAssertTrue(
            canBeginPhotoDismiss(zoomScale: 1, velocity: CGPoint(x: 20, y: 200))
        )
        XCTAssertFalse(
            canBeginPhotoDismiss(zoomScale: 2, velocity: CGPoint(x: 20, y: 200))
        )
        XCTAssertFalse(
            canBeginPhotoDismiss(zoomScale: 1, velocity: CGPoint(x: 20, y: -200))
        )
        XCTAssertFalse(
            canBeginPhotoDismiss(zoomScale: 1, velocity: CGPoint(x: 200, y: 40))
        )
    }

    private func shouldDismiss(
        translation: CGSize,
        projected: CGSize? = nil
    ) -> Bool {
        ViewerDismissGesturePolicy.shouldDismiss(
            translation: translation,
            projectedTranslation: projected ?? translation,
            viewportHeight: 800
        )
    }

    private func canBeginPhotoDismiss(
        zoomScale: CGFloat,
        velocity: CGPoint
    ) -> Bool {
        ViewerDismissGesturePolicy.canBeginPhotoDismiss(
            isEnabled: true,
            zoomScale: zoomScale,
            minimumZoomScale: 1,
            velocity: velocity
        )
    }
}
