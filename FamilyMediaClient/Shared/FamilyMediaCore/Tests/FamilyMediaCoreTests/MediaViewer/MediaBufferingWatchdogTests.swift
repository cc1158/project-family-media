import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaBufferingWatchdogTests {
    @Test func continuousWaitingTimesOutOnceAtConfiguredInterval() {
        let scheduler = WatchdogTestScheduler()
        let watchdog = MediaBufferingWatchdog(
            scheduler: scheduler,
            timeoutSeconds: 12
        )
        var timeoutCount = 0

        watchdog.update(activity: .waiting) {
            timeoutCount += 1
        }

        #expect(scheduler.scheduledSeconds == 12)
        scheduler.fire()
        scheduler.fire()
        #expect(timeoutCount == 1)
    }

    @Test func playingPausedAndExplicitCancellationDisarmPendingTimeout() {
        for activity in [MediaPlayerActivity.playing, .paused, .idle] {
            let scheduler = WatchdogTestScheduler()
            let watchdog = MediaBufferingWatchdog(scheduler: scheduler)
            var didTimeout = false

            watchdog.update(activity: .waiting) {
                didTimeout = true
            }
            watchdog.update(activity: activity) {
                didTimeout = true
            }
            scheduler.fireIgnoringCancellation()

            #expect(!didTimeout)
            #expect(scheduler.cancelCount >= 1)
        }

        let scheduler = WatchdogTestScheduler()
        let watchdog = MediaBufferingWatchdog(scheduler: scheduler)
        var didTimeout = false
        watchdog.update(activity: .waiting) {
            didTimeout = true
        }
        watchdog.cancel()
        scheduler.fireIgnoringCancellation()
        #expect(!didTimeout)
    }
}

@MainActor
private final class WatchdogTestScheduler: DelayedActionScheduling {
    private var action: (@MainActor () -> Void)?
    private var lastScheduledAction: (@MainActor () -> Void)?
    private(set) var scheduledSeconds: Int?
    private(set) var cancelCount = 0

    func schedule(afterSeconds seconds: Int, action: @escaping @MainActor () -> Void) {
        cancel()
        scheduledSeconds = seconds
        self.action = action
        lastScheduledAction = action
    }

    func cancel() {
        cancelCount += 1
        action = nil
    }

    func fire() {
        let pending = action
        action = nil
        pending?()
    }

    func fireIgnoringCancellation() {
        lastScheduledAction?()
    }
}
