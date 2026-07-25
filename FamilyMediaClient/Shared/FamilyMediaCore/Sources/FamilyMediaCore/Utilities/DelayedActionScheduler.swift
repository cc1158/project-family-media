import Combine
import Foundation

@MainActor
public protocol DelayedActionScheduling: AnyObject {
    func schedule(afterSeconds seconds: Int, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
public final class DelayedActionScheduler: ObservableObject, DelayedActionScheduling {
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    var hasPendingAction: Bool { task != nil }

    public init() {}

    deinit {
        task?.cancel()
    }

    public func schedule(
        afterSeconds seconds: Int,
        action: @escaping @MainActor () -> Void
    ) {
        cancel()

        let id = UUID()
        taskID = id
        task = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0, seconds)) * 1_000_000_000
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
            self?.finishTask(id: id)
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
    }

    private func finishTask(id: UUID) {
        guard taskID == id else { return }
        task = nil
        taskID = nil
    }
}
