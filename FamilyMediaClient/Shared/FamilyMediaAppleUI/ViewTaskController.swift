import Foundation

@MainActor
final class ViewTaskController: ObservableObject {
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    func run(_ operation: @escaping @MainActor () async -> Void) {
        start(operation)
    }

    func runAndWait(_ operation: @escaping @MainActor () async -> Void) async {
        let task = start(operation)
        await task.value
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
    }

    deinit {
        task?.cancel()
    }

    @discardableResult
    private func start(
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        cancel()
        let id = UUID()
        taskID = id
        let nextTask = Task { [weak self] in
            await operation()
            self?.finishTask(id: id)
        }
        task = nextTask
        return nextTask
    }

    private func finishTask(id: UUID) {
        guard taskID == id else { return }
        task = nil
        taskID = nil
    }
}
