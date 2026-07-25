import Testing
@testable import FamilyMediaCore

struct MediaViewerSessionTests {
    @Test func startsAtInitialItem() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")

        let session = MediaViewerSession(items: [first, second], initialItem: second)

        #expect(session.currentIndex == 1)
        #expect(session.currentItem == second)
        #expect(session.canGoPrevious)
        #expect(!session.canGoNext)
    }

    @Test func fallsBackToInitialItemWhenItemsAreEmpty() {
        let item = makeMediaItem(id: "only")

        let session = MediaViewerSession(items: [], initialItem: item)

        #expect(session.currentIndex == 0)
        #expect(session.currentItem == item)
        #expect(!session.canGoPrevious)
        #expect(!session.canGoNext)
    }

    @Test func manualNavigationMovesBetweenItems() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")
        var session = MediaViewerSession(items: [first, second], initialItem: first)

        session.goNextManually()
        #expect(session.currentItem == second)

        session.goPreviousManually()
        #expect(session.currentItem == first)
    }

    @Test func autoplayStartStopsAtLimit() {
        var session = MediaViewerSession(
            items: [makeMediaItem(id: "first")],
            initialItem: makeMediaItem(id: "first")
        )

        let firstStart = session.beginCurrentItemAutoplayIfAllowed(limit: 2)
        let secondStart = session.beginCurrentItemAutoplayIfAllowed(limit: 2)
        let thirdStart = session.beginCurrentItemAutoplayIfAllowed(limit: 2)

        #expect(firstStart)
        #expect(secondStart)
        #expect(!thirdStart)
        #expect(session.autoplayedItemCount == 2)
        #expect(session.hasReachedAutoplayLimit(2))
    }

    @Test func autoAdvanceStopsAtLimitOrEndOfList() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")
        let third = makeMediaItem(id: "third")
        var session = MediaViewerSession(items: [first, second, third], initialItem: first)

        let firstStart = session.beginCurrentItemAutoplayIfAllowed(limit: 2)
        let firstAdvance = session.advanceAutomaticallyIfPossible()

        #expect(firstStart)
        #expect(firstAdvance)
        #expect(session.currentItem == second)

        let secondStart = session.beginCurrentItemAutoplayIfAllowed(limit: 2)

        #expect(secondStart)
        #expect(session.hasReachedAutoplayLimit(2))
        #expect(session.currentItem == second)
    }

    @Test func manualNavigationResetsAutoplayCount() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")
        var session = MediaViewerSession(items: [first, second], initialItem: first)

        let firstStart = session.beginCurrentItemAutoplayIfAllowed(limit: 1)
        let secondStart = session.beginCurrentItemAutoplayIfAllowed(limit: 1)

        #expect(firstStart)
        #expect(!secondStart)

        session.goNextManually()

        let startAfterManualNavigation = session.beginCurrentItemAutoplayIfAllowed(limit: 1)

        #expect(startAfterManualNavigation)
        #expect(session.autoplayedItemCount == 1)
    }

    @Test func automaticAdvanceMovesThroughMixedMediaWithoutResettingCount() {
        let video = makeMediaItem(id: "video", kind: .video)
        let photo = makeMediaItem(id: "photo", kind: .photo)
        var session = MediaViewerSession(items: [video, photo], initialItem: video)

        let didStartVideo = session.beginCurrentItemAutoplayIfAllowed(limit: 2)
        let didAdvanceToPhoto = session.advanceAutomaticallyIfPossible()

        #expect(didStartVideo)
        #expect(didAdvanceToPhoto)
        #expect(session.currentItem == photo)
        #expect(session.autoplayedItemCount == 1)

        let didStartPhoto = session.beginCurrentItemAutoplayIfAllowed(limit: 2)

        #expect(didStartPhoto)
        #expect(session.hasReachedAutoplayLimit(2))
    }

    @Test func automaticAdvanceStopsAtEndOfList() {
        let item = makeMediaItem(id: "only")
        var session = MediaViewerSession(items: [item], initialItem: item)

        let didStart = session.beginCurrentItemAutoplayIfAllowed(limit: 20)
        let didAdvance = session.advanceAutomaticallyIfPossible()

        #expect(didStart)
        #expect(!didAdvance)
        #expect(session.currentItem == item)
    }

    @Test func continuingAfterLimitResetsCountAndAdvances() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")
        var session = MediaViewerSession(items: [first, second], initialItem: first)

        let didStartFirstWindow = session.beginCurrentItemAutoplayIfAllowed(limit: 1)
        #expect(didStartFirstWindow)
        #expect(session.hasReachedAutoplayLimit(1))
        let didContinue = session.continueAutoplayAfterLimitIfPossible()
        #expect(didContinue)
        #expect(session.currentItem == second)
        #expect(session.autoplayedItemCount == 0)
        let didStartSecondWindow = session.beginCurrentItemAutoplayIfAllowed(limit: 1)
        #expect(didStartSecondWindow)
    }
}
