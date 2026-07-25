import XCTest
@testable import FamilyMediaiOS

@MainActor
final class ViewTaskControllerTests: XCTestCase {
    func testCancelStopsRunningViewOperation() async {
        let controller = ViewTaskController()
        let cancelled = expectation(description: "view operation cancelled")

        controller.run {
            do {
                try await Task.sleep(for: .seconds(10))
                XCTFail("被取消的页面任务不应继续完成")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("预期 CancellationError，实际为 \(error)")
            }
        }

        await Task.yield()
        controller.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testRunAndWaitRemainsCancellableByOwningView() async {
        let controller = ViewTaskController()
        let started = expectation(description: "view operation started")
        let cancelled = expectation(description: "awaited view operation cancelled")

        let caller = Task { @MainActor in
            await controller.runAndWait {
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(10))
                    XCTFail("被取消的可等待页面任务不应继续完成")
                } catch is CancellationError {
                    cancelled.fulfill()
                } catch {
                    XCTFail("预期 CancellationError，实际为 \(error)")
                }
            }
        }

        await fulfillment(of: [started], timeout: 1)
        controller.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        await caller.value
    }

    func testReplacementCancelsPreviousAwaitedOperation() async {
        let controller = ViewTaskController()
        let firstStarted = expectation(description: "first operation started")
        let firstCancelled = expectation(description: "first operation cancelled")
        let replacementFinished = expectation(description: "replacement operation finished")

        let firstCaller = Task { @MainActor in
            await controller.runAndWait {
                firstStarted.fulfill()
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch is CancellationError {
                    firstCancelled.fulfill()
                } catch {
                    XCTFail("预期 CancellationError，实际为 \(error)")
                }
            }
        }

        await fulfillment(of: [firstStarted], timeout: 1)
        await controller.runAndWait {
            replacementFinished.fulfill()
        }

        await fulfillment(of: [firstCancelled, replacementFinished], timeout: 1)
        await firstCaller.value
    }
}
