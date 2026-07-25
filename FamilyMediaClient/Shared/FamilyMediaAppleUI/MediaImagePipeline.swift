import Foundation
import FamilyMediaCore
import ImageIO
import UIKit

final class SendableImage: @unchecked Sendable {
    let image: UIImage

    init(_ image: UIImage) {
        self.image = image
    }
}

struct MediaImageRequestKey: Hashable, Sendable {
    let rawValue: String

    init?(
        resourceRequest: MediaResourceRequest,
        maximumPixelSize: Int,
        cacheVersion: Int
    ) {
        guard let url = resourceRequest.request.url else { return nil }
        rawValue = [
            url.absoluteString,
            resourceRequest.cachePartition,
            String(maximumPixelSize),
            String(cacheVersion)
        ].joined(separator: "|")
    }

    var cacheKey: NSString {
        rawValue as NSString
    }
}

actor MediaImagePipeline {
    static let shared = MediaImagePipeline()

    typealias ProgressHandler = @Sendable (Double?) -> Void

    private struct Waiter {
        let continuation: CheckedContinuation<SendableImage, Error>
        let onProgress: ProgressHandler
    }

    private struct InFlightRequest {
        let id: UUID
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter]
        var progress = MediaImageProgressAccumulator()
    }

    nonisolated private let cache = ImageMemoryCache()
    private let session: URLSession
    private var inFlightRequests: [MediaImageRequestKey: InFlightRequest] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: configuration)
    }

    func image(
        at url: URL,
        maximumPixelSize: Int,
        cacheVersion: Int,
        usesFileBackedDownload: Bool
    ) async throws -> SendableImage {
        try await image(
            resourceRequest: .unauthenticated(url: url),
            maximumPixelSize: maximumPixelSize,
            cacheVersion: cacheVersion,
            usesFileBackedDownload: usesFileBackedDownload
        )
    }

    func image(
        resourceRequest: MediaResourceRequest,
        maximumPixelSize: Int,
        cacheVersion: Int,
        usesFileBackedDownload: Bool,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> SendableImage {
        guard let key = MediaImageRequestKey(
            resourceRequest: resourceRequest,
            maximumPixelSize: maximumPixelSize,
            cacheVersion: cacheVersion
        ) else {
            throw URLError(.badURL)
        }
        if let cached = cache.object(forKey: key.cacheKey) {
            onProgress(1)
            return cached
        }

        var request = resourceRequest.request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let waiterID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerWaiter(
                    continuation,
                    id: waiterID,
                    key: key,
                    resourceRequest: MediaResourceRequest(
                        request: request,
                        cachePartition: resourceRequest.cachePartition,
                        unauthorizedResponseHandler: resourceRequest.handleUnauthorizedResponse
                    ),
                    maximumPixelSize: maximumPixelSize,
                    usesFileBackedDownload: usesFileBackedDownload,
                    onProgress: onProgress
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID, key: key) }
        }
    }

    nonisolated func cachedImage(
        resourceRequest: MediaResourceRequest,
        maximumPixelSize: Int,
        cacheVersion: Int
    ) -> SendableImage? {
        guard let key = MediaImageRequestKey(
            resourceRequest: resourceRequest,
            maximumPixelSize: maximumPixelSize,
            cacheVersion: cacheVersion
        ) else {
            return nil
        }
        return cache.object(forKey: key.cacheKey)
    }

    private func registerWaiter(
        _ continuation: CheckedContinuation<SendableImage, Error>,
        id: UUID,
        key: MediaImageRequestKey,
        resourceRequest: MediaResourceRequest,
        maximumPixelSize: Int,
        usesFileBackedDownload: Bool,
        onProgress: @escaping ProgressHandler
    ) {
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }

        if var inFlight = inFlightRequests[key] {
            inFlight.waiters[id] = Waiter(
                continuation: continuation,
                onProgress: onProgress
            )
            if case let .some(progress) = inFlight.progress.latestReport {
                onProgress(progress)
            }
            inFlightRequests[key] = inFlight
            return
        }

        let requestID = UUID()
        inFlightRequests[key] = InFlightRequest(
            id: requestID,
            task: nil,
            waiters: [
                id: Waiter(
                    continuation: continuation,
                    onProgress: onProgress
                )
            ]
        )
        let task = Task {
            let result: Result<SendableImage, Error>
            do {
                let image = try await loadImage(
                    resourceRequest: resourceRequest,
                    maximumPixelSize: maximumPixelSize,
                    usesFileBackedDownload: usesFileBackedDownload,
                    onDownloadProgress: { [weak self] received, expected in
                        Task {
                            await self?.publishProgress(
                                forKey: key,
                                requestID: requestID,
                                receivedBytes: received,
                                expectedBytes: expected
                            )
                        }
                    }
                )
                publishProgress(
                    forKey: key,
                    requestID: requestID,
                    fraction: 1
                )
                result = .success(SendableImage(image))
            } catch {
                result = .failure(error)
            }
            finishRequest(forKey: key, requestID: requestID, result: result)
        }
        inFlightRequests[key]?.task = task
    }

    private func cancelWaiter(id: UUID, key: MediaImageRequestKey) {
        guard var inFlight = inFlightRequests[key],
              let waiter = inFlight.waiters.removeValue(forKey: id)
        else { return }

        waiter.continuation.resume(throwing: CancellationError())
        if inFlight.waiters.isEmpty {
            inFlight.task?.cancel()
            inFlightRequests.removeValue(forKey: key)
        } else {
            inFlightRequests[key] = inFlight
        }
    }

    private func finishRequest(
        forKey key: MediaImageRequestKey,
        requestID: UUID,
        result: Result<SendableImage, Error>
    ) {
        guard let inFlight = inFlightRequests[key], inFlight.id == requestID else {
            return
        }
        inFlightRequests.removeValue(forKey: key)

        if case let .success(image) = result {
            cache.setObject(
                image,
                forKey: key.cacheKey,
                cost: Self.estimatedCost(of: image.image)
            )
        }
        inFlight.waiters.values.forEach { $0.continuation.resume(with: result) }
    }

    private func publishProgress(
        forKey key: MediaImageRequestKey,
        requestID: UUID,
        receivedBytes: Int64,
        expectedBytes: Int64
    ) {
        let fraction = expectedBytes > 0
            ? Double(receivedBytes) / Double(expectedBytes)
            : nil
        publishProgress(
            forKey: key,
            requestID: requestID,
            fraction: fraction
        )
    }

    private func publishProgress(
        forKey key: MediaImageRequestKey,
        requestID: UUID,
        fraction: Double?
    ) {
        guard var inFlight = inFlightRequests[key], inFlight.id == requestID else {
            return
        }

        switch inFlight.progress.record(fraction) {
        case .ignored:
            return
        case .report(let progress):
            inFlightRequests[key] = inFlight
            inFlight.waiters.values.forEach { $0.onProgress(progress) }
        }
    }

    private func loadImage(
        resourceRequest: MediaResourceRequest,
        maximumPixelSize: Int,
        usesFileBackedDownload: Bool,
        onDownloadProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> UIImage {
        let request = resourceRequest.request
        if usesFileBackedDownload {
            let delegate = MediaImageDownloadProgressDelegate(
                onProgress: onDownloadProgress
            )
            let (temporaryURL, response) = try await session.download(
                for: request,
                delegate: delegate
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try Task.checkCancellation()
            Self.handleUnauthorized(response, resourceRequest: resourceRequest)
            try Self.validate(response)
            guard let image = Self.downsample(
                fileURL: temporaryURL,
                maximumPixelSize: maximumPixelSize
            ) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        Self.handleUnauthorized(response, resourceRequest: resourceRequest)
        try Self.validate(response)
        guard let image = Self.downsample(data: data, maximumPixelSize: maximumPixelSize) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    private nonisolated static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
    }

    private nonisolated static func handleUnauthorized(
        _ response: URLResponse,
        resourceRequest: MediaResourceRequest
    ) {
        guard (response as? HTTPURLResponse)?.statusCode == 401 else { return }
        resourceRequest.handleUnauthorizedResponse()
    }

    private nonisolated static func downsample(data: Data, maximumPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return downsample(source: source, maximumPixelSize: maximumPixelSize)
    }

    private nonisolated static func downsample(
        fileURL: URL,
        maximumPixelSize: Int
    ) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        return downsample(source: source, maximumPixelSize: maximumPixelSize)
    }

    private nonisolated static func downsample(
        source: CGImageSource,
        maximumPixelSize: Int
    ) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private nonisolated static func estimatedCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
