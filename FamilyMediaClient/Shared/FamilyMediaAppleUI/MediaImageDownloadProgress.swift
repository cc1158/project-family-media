import Foundation

enum MediaImageProgressUpdate: Equatable {
    case ignored
    case report(Double?)
}

struct MediaImageProgressAccumulator {
    private(set) var lastDeterminate: Double?
    private(set) var didReportIndeterminate = false

    var latestReport: Double?? {
        if let lastDeterminate {
            return .some(lastDeterminate)
        }
        return didReportIndeterminate ? .some(nil) : nil
    }

    mutating func record(_ fraction: Double?) -> MediaImageProgressUpdate {
        guard let fraction else {
            guard !didReportIndeterminate else { return .ignored }
            didReportIndeterminate = true
            return .report(nil)
        }

        let normalized = min(max(0, fraction), 1)
        if let lastDeterminate {
            guard normalized >= lastDeterminate else { return .ignored }
            guard normalized == 1 || normalized - lastDeterminate >= 0.02 else {
                return .ignored
            }
        }
        lastDeterminate = normalized
        return .report(normalized)
    }
}

final class MediaImageDownloadProgressDelegate:
    NSObject,
    URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
