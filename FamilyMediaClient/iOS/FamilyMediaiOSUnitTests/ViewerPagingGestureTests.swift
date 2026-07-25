import XCTest
@testable import FamilyMediaiOS

final class ViewerPagingGestureTests: XCTestCase {
    func testDistanceAndProjectionCommitExpectedDirection() {
        XCTAssertEqual(
            decision(translation: CGSize(width: -180, height: 20)),
            .next
        )
        XCTAssertEqual(
            decision(
                translation: CGSize(width: 30, height: 2),
                projected: CGSize(width: 180, height: 8)
            ),
            .previous
        )
    }

    func testVerticalAndShortDragsDoNotPage() {
        XCTAssertNil(decision(translation: CGSize(width: 40, height: 80)))
        XCTAssertNil(decision(translation: CGSize(width: 50, height: 3)))
    }

    func testPredictionCannotReverseVisibleDragDirection() {
        XCTAssertEqual(
            decision(
                translation: CGSize(width: 90, height: 0),
                projected: CGSize(width: -220, height: 0)
            ),
            .previous
        )
    }

    func testUnavailableBoundaryUsesResistanceAndNeverCommits() {
        XCTAssertEqual(
            ViewerPagingGesturePolicy.offset(
                for: CGSize(width: 100, height: 0),
                canGoPrevious: false,
                canGoNext: true
            ),
            18,
            accuracy: 0.001
        )
        XCTAssertNil(
            decision(
                translation: CGSize(width: 200, height: 0),
                canGoPrevious: false
            )
        )
    }

    func testAccessibilityAndConflictingInteractionsDisablePaging() {
        XCTAssertFalse(isEnabled(isVoiceOverEnabled: true))
        XCTAssertFalse(isEnabled(isPhotoInspectionActive: true))
        XCTAssertFalse(isEnabled(isScrubbing: true))
        XCTAssertFalse(isEnabled(isOverlayPresented: true))
        XCTAssertFalse(isEnabled(isTransitioning: true))
        XCTAssertTrue(isEnabled())
    }

    func testInteractionStateIgnoresUpdatesDuringTransition() {
        var state = ViewerPagingPresentationState()
        state.update(
            translation: CGSize(width: -100, height: 0),
            canGoPrevious: true,
            canGoNext: true
        )
        XCTAssertEqual(state.offset, -100)
        XCTAssertEqual(state.previewDirection, .next)

        state.beginTransition(direction: .next, width: 390)
        state.update(
            translation: CGSize(width: 80, height: 0),
            canGoPrevious: true,
            canGoNext: true
        )
        XCTAssertEqual(state.offset, -390)
        XCTAssertTrue(state.isTransitioning)

        state.resetVisualState()
        XCTAssertEqual(state, ViewerPagingPresentationState())
    }

    func testPresentationStateKeepsChromeIntentUntilItemChange() {
        var state = ViewerPagingPresentationState()
        state.prepareForItemChange()
        state.beginTransition(direction: .next, width: 390)
        state.resetVisualState()

        XCTAssertTrue(state.resetForItemChange())
        XCTAssertFalse(state.resetForItemChange())
        XCTAssertEqual(state, ViewerPagingPresentationState())
    }

    func testPhotoPagingBeginsOnlyAtOriginalZoomForHorizontalPan() {
        XCTAssertTrue(
            ViewerPagingGesturePolicy.canBeginPhotoPaging(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 300, y: 40)
            )
        )
        XCTAssertFalse(
            ViewerPagingGesturePolicy.canBeginPhotoPaging(
                isEnabled: true,
                zoomScale: 2,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 300, y: 40)
            )
        )
        XCTAssertFalse(
            ViewerPagingGesturePolicy.canBeginPhotoPaging(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 40, y: 300)
            )
        )
        XCTAssertTrue(
            ViewerPagingGesturePolicy.canBeginPhotoPaging(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 5, y: 1)
            )
        )
        XCTAssertFalse(
            ViewerPagingGesturePolicy.canBeginPhotoPaging(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: .zero
            )
        )
    }

    func testPhotoNavigationComposesHorizontalPagingAndDownwardDismiss() {
        XCTAssertTrue(
            ViewerNavigationGesturePolicy.canBeginPhotoNavigation(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 240, y: 20)
            )
        )
        XCTAssertTrue(
            ViewerNavigationGesturePolicy.canBeginPhotoNavigation(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 20, y: 240)
            )
        )
        XCTAssertFalse(
            ViewerNavigationGesturePolicy.canBeginPhotoNavigation(
                isEnabled: true,
                zoomScale: 1,
                minimumZoomScale: 1,
                velocity: CGPoint(x: 20, y: -240)
            )
        )
    }

    private func decision(
        translation: CGSize,
        projected: CGSize? = nil,
        canGoPrevious: Bool = true,
        canGoNext: Bool = true
    ) -> ViewerPagingDirection? {
        ViewerPagingGesturePolicy.decision(
            translation: translation,
            projectedTranslation: projected ?? translation,
            viewportWidth: 390,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
    }

    private func isEnabled(
        isVoiceOverEnabled: Bool = false,
        isPhotoInspectionActive: Bool = false,
        isScrubbing: Bool = false,
        isOverlayPresented: Bool = false,
        isTransitioning: Bool = false
    ) -> Bool {
        ViewerNavigationGesturePolicy.isEnabled(
            isVoiceOverEnabled: isVoiceOverEnabled,
            isPhotoInspectionActive: isPhotoInspectionActive,
            isScrubbing: isScrubbing,
            isOverlayPresented: isOverlayPresented,
            isTransitioning: isTransitioning
        )
    }
}
