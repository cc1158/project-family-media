import Foundation

public enum TaskCancellation {
    public static func matches(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}
