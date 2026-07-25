import Testing
@testable import FamilyMediaCore

@MainActor
struct DelayedActionSchedulerTests {
    @Test func completedActionReleasesStoredTask() async throws {
        let scheduler = DelayedActionScheduler()
        var actionCount = 0

        scheduler.schedule(afterSeconds: 0) {
            actionCount += 1
        }

        try await waitUntil {
            actionCount == 1 && !scheduler.hasPendingAction
        }
        #expect(actionCount == 1)
        #expect(!scheduler.hasPendingAction)
    }

    @Test func replacementDoesNotLetOldTaskClearNewAction() async throws {
        let scheduler = DelayedActionScheduler()
        var actionCount = 0

        scheduler.schedule(afterSeconds: 0) {
            scheduler.schedule(afterSeconds: 0) {
                actionCount += 1
            }
        }

        try await waitUntil {
            actionCount == 1 && !scheduler.hasPendingAction
        }
        #expect(actionCount == 1)
        #expect(!scheduler.hasPendingAction)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待延时任务释放超时")
    }
}
