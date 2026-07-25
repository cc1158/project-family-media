import XCTest
@testable import FamilyMediaiOS

final class MediaImageProgressTests: XCTestCase {
    func testProgressPolicyReportsUnknownSizeOnce() {
        var progress = MediaImageProgressAccumulator()

        XCTAssertEqual(progress.record(nil), .report(nil))
        XCTAssertEqual(progress.record(nil), .ignored)
        XCTAssertEqual(progress.latestReport!, nil)
    }

    func testProgressPolicyIsMonotonicThrottledAndCompletesAtOne() {
        var progress = MediaImageProgressAccumulator()

        XCTAssertEqual(progress.record(0.1), .report(0.1))
        XCTAssertEqual(progress.record(0.11), .ignored)
        XCTAssertEqual(progress.record(0.08), .ignored)
        XCTAssertEqual(progress.record(0.12), .ignored)
        XCTAssertEqual(progress.record(0.121), .report(0.121))
        XCTAssertEqual(progress.record(2), .report(1))
        XCTAssertEqual(progress.latestReport!, 1)
    }
}
