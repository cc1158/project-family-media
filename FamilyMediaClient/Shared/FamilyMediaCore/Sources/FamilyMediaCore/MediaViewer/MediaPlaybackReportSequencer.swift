import Foundation

@MainActor
final class MediaPlaybackReportSequencer {
    private enum OperationKind {
        case lifecycle
        case progress
        case stop
    }

    private struct QueuedOperation {
        let kind: OperationKind
        let action: @Sendable () async -> Void
    }

    private var queuedOperations: [QueuedOperation] = []
    private var workerTask: Task<Void, Never>?
    private var activeOperationTask: Task<Void, Never>?
    private var activeOperationKind: OperationKind?

    func enqueueLifecycle(_ operation: @escaping @Sendable () async -> Void) {
        enqueue(kind: .lifecycle, operation)
    }

    func enqueueProgress(_ operation: @escaping @Sendable () async -> Void) {
        queuedOperations.removeAll { $0.kind == .progress }
        enqueue(kind: .progress, operation)
    }

    func enqueueStop(_ operation: @escaping @Sendable () async -> Void) {
        // The stopped report already carries the latest playback position. Sending
        // older queued progress first only delays Jellyfin from releasing FFmpeg.
        // Cancel an in-flight progress request as well: URLSession propagates task
        // cancellation to the request, allowing the stop report to release a
        // transcoder without waiting for the normal network timeout.
        queuedOperations.removeAll { $0.kind == .progress }
        enqueue(kind: .stop, operation)
        if activeOperationKind == .progress {
            activeOperationTask?.cancel()
        }
    }

    func waitForPendingReports() async {
        while let workerTask {
            await workerTask.value
        }
    }

    private func enqueue(
        kind: OperationKind,
        _ operation: @escaping @Sendable () async -> Void
    ) {
        queuedOperations.append(QueuedOperation(kind: kind, action: operation))
        guard workerTask == nil else { return }
        workerTask = Task {
            await drainQueue()
        }
    }

    private func drainQueue() async {
        while !queuedOperations.isEmpty {
            let operation = queuedOperations.removeFirst()
            activeOperationKind = operation.kind
            let operationTask = Task {
                await operation.action()
            }
            activeOperationTask = operationTask
            await operationTask.value
            activeOperationTask = nil
            activeOperationKind = nil
        }
        workerTask = nil
    }
}
