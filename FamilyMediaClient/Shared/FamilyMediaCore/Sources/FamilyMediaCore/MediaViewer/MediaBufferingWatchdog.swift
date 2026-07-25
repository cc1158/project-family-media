import Foundation

@MainActor
final class MediaBufferingWatchdog {
    static let defaultTimeoutSeconds = 30

    private let scheduler: any DelayedActionScheduling
    private let timeoutSeconds: Int
    private var isWaiting = false

    init(
        scheduler: any DelayedActionScheduling = DelayedActionScheduler(),
        timeoutSeconds: Int = defaultTimeoutSeconds
    ) {
        self.scheduler = scheduler
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    func update(
        activity: MediaPlayerActivity,
        onTimeout: @escaping @MainActor () -> Void
    ) {
        guard activity == .waiting else {
            cancel()
            return
        }

        isWaiting = true
        scheduler.schedule(afterSeconds: timeoutSeconds) { [weak self] in
            guard let self, isWaiting else { return }
            isWaiting = false
            onTimeout()
        }
    }

    func cancel() {
        isWaiting = false
        scheduler.cancel()
    }
}
