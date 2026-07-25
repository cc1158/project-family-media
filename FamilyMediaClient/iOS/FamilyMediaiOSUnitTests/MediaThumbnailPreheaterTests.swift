import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

final class MediaThumbnailPreheaterTests: XCTestCase {
    func testViewerPolicyBuildsExpectedPriorityAndClampsInvalidValues() {
        XCTAssertEqual(
            MediaThumbnailPreheatPolicy.viewer.orderedOffsets,
            [1, -1, 2, -2, 3, 4]
        )

        let clamped = MediaThumbnailPreheatPolicy(
            previousItemCount: -1,
            nextItemCount: -2,
            maximumConcurrentRequests: 0
        )
        XCTAssertEqual(clamped.previousItemCount, 0)
        XCTAssertEqual(clamped.nextItemCount, 0)
        XCTAssertEqual(clamped.maximumConcurrentRequests, 1)
        XCTAssertTrue(clamped.orderedOffsets.isEmpty)
    }

    func testPlannerUsesTwoPreviousAndFourNextItemsInPriorityOrder() {
        let items = (0..<9).map(makeItem)

        let candidates = MediaThumbnailPreheatPlanner.candidates(
            items: items,
            currentIndex: 3,
            requestAuthorizer: nil
        )

        XCTAssertEqual(
            candidates.compactMap { $0.resourceRequest.request.url?.lastPathComponent },
            ["4.jpg", "2.jpg", "5.jpg", "1.jpg", "6.jpg", "7.jpg"]
        )
    }

    func testPlannerClampsAtSequenceBoundaries() {
        let items = (0..<6).map(makeItem)

        let fromStart = MediaThumbnailPreheatPlanner.candidates(
            items: items,
            currentIndex: 0,
            requestAuthorizer: nil
        )
        let fromEnd = MediaThumbnailPreheatPlanner.candidates(
            items: items,
            currentIndex: 5,
            requestAuthorizer: nil
        )

        XCTAssertEqual(
            fromStart.compactMap { $0.resourceRequest.request.url?.lastPathComponent },
            ["1.jpg", "2.jpg", "3.jpg", "4.jpg"]
        )
        XCTAssertEqual(
            fromEnd.compactMap { $0.resourceRequest.request.url?.lastPathComponent },
            ["4.jpg", "3.jpg"]
        )
    }

    func testPlannerSkipsUnavailableAndDemoThumbnails() {
        var items = (0..<5).map(makeItem)
        items[1] = makeItem(index: 1, thumbnailStatus: .pending)
        items[2] = makeItem(index: 2, thumbnailURL: URL(string: "demo-art://photo/2")!)

        let candidates = MediaThumbnailPreheatPlanner.candidates(
            items: items,
            currentIndex: 0,
            requestAuthorizer: nil
        )

        XCTAssertEqual(
            candidates.compactMap { $0.resourceRequest.request.url?.lastPathComponent },
            ["3.jpg", "4.jpg"]
        )
    }

    @MainActor
    func testControllerStartsOnlyTwoRequestsAndUsesPlannerPriority() async throws {
        let recorder = ThumbnailPreheatRecorder(delay: .milliseconds(120))
        let controller = MediaThumbnailPreheater(
            imageProvider: { request in
                try await recorder.load(request)
            },
            isCached: { _ in false }
        )

        controller.update(
            items: (0..<9).map(makeItem),
            currentIndex: 3,
            requestAuthorizer: nil
        )
        try await Task.sleep(for: .milliseconds(30))

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.started, ["4.jpg", "2.jpg"])
        XCTAssertEqual(snapshot.maximumActive, 2)
        controller.cancel()
    }

    @MainActor
    func testControllerSkipsCachedCandidatesWithoutConsumingConcurrency() async throws {
        let recorder = ThumbnailPreheatRecorder(delay: .milliseconds(120))
        let controller = MediaThumbnailPreheater(
            imageProvider: { request in
                try await recorder.load(request)
            },
            isCached: { request in
                request.request.url?.lastPathComponent == "4.jpg"
            }
        )

        controller.update(
            items: (0..<9).map(makeItem),
            currentIndex: 3,
            requestAuthorizer: nil
        )
        try await Task.sleep(for: .milliseconds(30))

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.started, ["2.jpg", "5.jpg"])
        XCTAssertEqual(snapshot.maximumActive, 2)
        controller.cancel()
    }

    @MainActor
    func testChangingWindowRetainsOverlappingActiveRequest() async throws {
        let recorder = ThumbnailPreheatRecorder(delay: .seconds(1))
        let controller = MediaThumbnailPreheater(
            imageProvider: { request in
                try await recorder.load(request)
            },
            isCached: { _ in false }
        )
        let items = (0..<10).map(makeItem)

        controller.update(items: items, currentIndex: 3, requestAuthorizer: nil)
        try await Task.sleep(for: .milliseconds(30))
        controller.update(items: items, currentIndex: 4, requestAuthorizer: nil)
        try await Task.sleep(for: .milliseconds(30))

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.started.filter { $0 == "2.jpg" }.count, 1)
        XCTAssertFalse(snapshot.cancelled.contains("2.jpg"))
        controller.cancel()
    }

    @MainActor
    func testChangingWindowCancelsObsoleteRequests() async throws {
        let recorder = ThumbnailPreheatRecorder(delay: .seconds(1))
        let controller = MediaThumbnailPreheater(
            imageProvider: { request in
                try await recorder.load(request)
            },
            isCached: { _ in false }
        )
        let items = (0..<10).map(makeItem)

        controller.update(items: items, currentIndex: 2, requestAuthorizer: nil)
        try await Task.sleep(for: .milliseconds(30))
        controller.update(items: items, currentIndex: 9, requestAuthorizer: nil)
        try await Task.sleep(for: .milliseconds(30))

        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.cancelled.contains("3.jpg"))
        XCTAssertTrue(snapshot.cancelled.contains("1.jpg"))
        controller.cancel()
    }

    private func makeItem(_ index: Int) -> MediaItem {
        makeItem(index: index)
    }

    private func makeItem(
        index: Int,
        thumbnailStatus: ThumbnailStatus = .ready,
        thumbnailURL: URL? = nil
    ) -> MediaItem {
        MediaItem(
            id: "item-\(index)",
            name: "\(index)",
            kind: index.isMultiple(of: 2) ? .photo : .video,
            size: 1,
            modified: Date(timeIntervalSince1970: TimeInterval(index)),
            url: URL(string: "https://images.example/original/\(index).jpg")!,
            thumbnailURL: thumbnailURL
                ?? URL(string: "https://images.example/thumbnail/\(index).jpg")!,
            mediaPath: "\(index).jpg",
            thumbnailStatus: thumbnailStatus
        )
    }
}

private actor ThumbnailPreheatRecorder {
    struct Snapshot {
        let started: [String]
        let cancelled: [String]
        let maximumActive: Int
    }

    private let delay: Duration
    private var started: [String] = []
    private var cancelled: [String] = []
    private var active = 0
    private var maximumActive = 0

    init(delay: Duration) {
        self.delay = delay
    }

    func load(_ request: MediaResourceRequest) async throws {
        let name = request.request.url?.lastPathComponent ?? "unknown"
        started.append(name)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }

        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            cancelled.append(name)
            throw CancellationError()
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            started: started,
            cancelled: cancelled,
            maximumActive: maximumActive
        )
    }
}
