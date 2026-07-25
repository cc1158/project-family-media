import Foundation
import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

final class MediaImagePipelineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ImageStubURLProtocol.reset()
    }

    override func tearDown() {
        ImageStubURLProtocol.reset()
        super.tearDown()
    }

    func testImagePurposesUseMemoryConsciousDecodeSizes() {
        XCTAssertEqual(CachedRemoteImagePurpose.thumbnail.maximumPixelSize, 800)
        XCTAssertEqual(CachedRemoteImagePurpose.photoViewer.maximumPixelSize, 4_096)
        XCTAssertFalse(CachedRemoteImagePurpose.thumbnail.usesFileBackedDownload)
        XCTAssertTrue(CachedRemoteImagePurpose.photoViewer.usesFileBackedDownload)
    }

    func testMemoryCacheCanBeClearedWithoutChangingPipelinePolicy() {
        let cache = ImageMemoryCache()
        let key = "thumbnail" as NSString
        cache.setObject(SendableImage(UIImage()), forKey: key, cost: 1)
        XCTAssertNotNil(cache.object(forKey: key))

        cache.removeAllObjects()

        XCTAssertNil(cache.object(forKey: key))
    }

    func testSameCacheVersionLoadsOnceAndNewVersionReloads() async throws {
        let pipeline = makePipeline()
        let url = URL(string: "https://images.example/cover.png")!

        _ = try await pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )
        _ = try await pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 1)

        _ = try await pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 1,
            usesFileBackedDownload: false
        )
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 2)
    }

    func testLoadedThumbnailIsSynchronouslyAvailableForTheSameCacheKey() async throws {
        let pipeline = makePipeline()
        let request = MediaResourceRequest.unauthenticated(
            url: URL(string: "https://images.example/preheated.png")!
        )

        _ = try await pipeline.image(
            resourceRequest: request,
            maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )

        XCTAssertNotNil(
            pipeline.cachedImage(
                resourceRequest: request,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: 0
            )
        )
        XCTAssertNil(
            pipeline.cachedImage(
                resourceRequest: MediaResourceRequest(
                    request: request.request,
                    cachePartition: "different-session"
                ),
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: 0
            )
        )
        XCTAssertNil(
            pipeline.cachedImage(
                resourceRequest: request,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: 1
            )
        )
    }

    func testPhotoViewerUsesFileBackedDownloadAndProducesImage() async throws {
        let pipeline = makePipeline()
        let result = try await pipeline.image(
            at: URL(string: "https://images.example/photo.png")!,
            maximumPixelSize: 4_096,
            cacheVersion: 0,
            usesFileBackedDownload: true
        )

        XCTAssertEqual(result.image.size.width, 1)
        XCTAssertEqual(result.image.size.height, 1)
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 1)
    }

    func testProtectedImageUsesHeaderAndSessionPartitionedCache() async throws {
        let pipeline = makePipeline()
        let url = URL(string: "https://images.example/protected-cover.png")!
        var firstRequest = URLRequest(url: url)
        firstRequest.setValue("MediaBrowser Token=\"token-one\"", forHTTPHeaderField: "Authorization")

        _ = try await pipeline.image(
            resourceRequest: MediaResourceRequest(
                request: firstRequest,
                cachePartition: "session-one"
            ),
            maximumPixelSize: 800,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )
        _ = try await pipeline.image(
            resourceRequest: MediaResourceRequest(
                request: URLRequest(url: url),
                cachePartition: "session-two"
            ),
            maximumPixelSize: 800,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )

        XCTAssertEqual(ImageStubURLProtocol.requestCount, 2)
        XCTAssertEqual(
            ImageStubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "MediaBrowser Token=\"token-one\""
        )
        XCTAssertNil(ImageStubURLProtocol.requests.first?.url?.query)
    }

    func testUnauthorizedProtectedImageNotifiesSessionLayer() async {
        ImageStubURLProtocol.setStatusCode(401)
        let pipeline = makePipeline()
        let notification = expectation(description: "Jellyfin session invalidated")
        let resourceRequest = MediaResourceRequest(
            request: URLRequest(url: URL(string: "https://images.example/expired-cover.png")!),
            cachePartition: "expired-session",
            unauthorizedResponseHandler: {
                notification.fulfill()
            }
        )

        do {
            _ = try await pipeline.image(
                resourceRequest: resourceRequest,
                maximumPixelSize: 800,
                cacheVersion: 0,
                usesFileBackedDownload: false
            )
            XCTFail("401 图片请求应失败")
        } catch {
            // The image failure remains visible while the session layer updates login state.
        }

        await fulfillment(of: [notification], timeout: 1)
    }

    func testConcurrentRequestsForSameImageShareOneDownload() async throws {
        ImageStubURLProtocol.setResponseDelay(0.1)
        let pipeline = makePipeline()
        let url = URL(string: "https://images.example/shared-cover.png")!

        async let first = pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )
        async let second = pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )

        _ = try await (first, second)
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 1)
    }

    func testCancellingOneSharedWaiterDoesNotCancelRemainingViewer() async throws {
        ImageStubURLProtocol.setResponseDelay(0.1)
        let pipeline = makePipeline()
        let url = URL(string: "https://images.example/shared-photo.png")!
        let first = Task {
            try await pipeline.image(
                at: url,
                maximumPixelSize: 4_096,
                cacheVersion: 0,
                usesFileBackedDownload: false
            )
        }
        let second = Task {
            try await pipeline.image(
                at: url,
                maximumPixelSize: 4_096,
                cacheVersion: 0,
                usesFileBackedDownload: false
            )
        }

        try await Task.sleep(for: .milliseconds(20))
        first.cancel()

        do {
            _ = try await first.value
            XCTFail("已取消的图片等待者应收到 CancellationError")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await second.value
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 1)
    }

    func testCancellingLastWaiterStopsUnderlyingTransfer() async throws {
        ImageStubURLProtocol.setResponseDelay(1)
        let pipeline = makePipeline()
        let task = Task {
            try await pipeline.image(
                at: URL(string: "https://images.example/abandoned-cover.png")!,
                maximumPixelSize: 1_200,
                cacheVersion: 0,
                usesFileBackedDownload: false
            )
        }

        try await waitUntil { ImageStubURLProtocol.requestCount == 1 }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("最后一个等待者取消后应结束图片加载")
        } catch is CancellationError {
            // Expected.
        }
        try await waitUntil { ImageStubURLProtocol.stopCount == 1 }
    }

    func testImmediateRetryAfterLastWaiterCancellationUsesReplacementRequest() async throws {
        ImageStubURLProtocol.setResponseDelays([1, 0])
        let pipeline = makePipeline()
        let url = URL(string: "https://images.example/reopened-cover.png")!
        let abandoned = Task {
            try await pipeline.image(
                at: url,
                maximumPixelSize: 1_200,
                cacheVersion: 0,
                usesFileBackedDownload: false
            )
        }

        try await waitUntil { ImageStubURLProtocol.requestCount == 1 }
        abandoned.cancel()
        do {
            _ = try await abandoned.value
            XCTFail("离屏请求应被取消")
        } catch is CancellationError {
            // Expected.
        }

        let replacement = try await pipeline.image(
            at: url,
            maximumPixelSize: 1_200,
            cacheVersion: 0,
            usesFileBackedDownload: false
        )

        XCTAssertEqual(replacement.image.size.width, 1)
        XCTAssertEqual(ImageStubURLProtocol.requestCount, 2)
    }

    @MainActor
    func testImageLoaderNeverPresentsStateFromPreviousRequestIdentity() async {
        let loader = CachedRemoteImageLoader()

        await loader.load(
            url: nil,
            purpose: .thumbnail,
            cacheVersion: 0,
            requestID: "old-cover"
        )

        if case .failure = loader.phase(for: "old-cover") {
            // Expected state for the completed old request.
        } else {
            XCTFail("旧请求本身应保留失败状态")
        }

        if case .empty = loader.phase(for: "new-cover") {
            // A recycled view must show its placeholder until the new task starts.
        } else {
            XCTFail("新媒体项不得短暂显示旧请求的图片状态")
        }
    }

    @MainActor
    func testLateImageFromReusedViewCannotOverwriteCurrentRequest() async throws {
        let oldImage = SendableImage(UIImage())
        let currentImage = SendableImage(UIImage())
        let loader = CachedRemoteImageLoader { resourceRequest, _, _ in
            if resourceRequest.request.url?.lastPathComponent == "old.png" {
                try await Task.sleep(for: .milliseconds(50))
                return oldImage
            }
            return currentImage
        }
        let oldRequest = Task { @MainActor in
            await loader.load(
                url: URL(string: "https://images.example/old.png"),
                purpose: .thumbnail,
                cacheVersion: 0,
                requestID: "old-cover"
            )
        }

        try await Task.sleep(for: .milliseconds(5))
        await loader.load(
            url: URL(string: "https://images.example/current.png"),
            purpose: .thumbnail,
            cacheVersion: 0,
            requestID: "current-cover"
        )
        await oldRequest.value

        guard case let .success(displayedImage) = loader.phase(for: "current-cover") else {
            return XCTFail("复用后的卡片应显示当前请求的封面")
        }
        XCTAssertTrue(displayedImage === currentImage.image)
        XCTAssertFalse(displayedImage === oldImage.image)
    }

    @MainActor
    func testLateFailureCannotFailReplacementRequestStillLoading() async throws {
        let currentImage = SendableImage(UIImage())
        let loader = CachedRemoteImageLoader { resourceRequest, _, _ in
            if resourceRequest.request.url?.lastPathComponent == "old.png" {
                try await Task.sleep(for: .milliseconds(20))
                throw URLError(.badServerResponse)
            }
            try await Task.sleep(for: .milliseconds(80))
            return currentImage
        }
        let oldRequest = Task { @MainActor in
            await loader.load(
                url: URL(string: "https://images.example/old.png"),
                purpose: .thumbnail,
                cacheVersion: 0,
                requestID: "old-cover"
            )
        }

        try await Task.sleep(for: .milliseconds(5))
        let currentRequest = Task { @MainActor in
            await loader.load(
                url: URL(string: "https://images.example/current.png"),
                purpose: .thumbnail,
                cacheVersion: 0,
                requestID: "current-cover"
            )
        }
        try await Task.sleep(for: .milliseconds(35))

        if case .empty = loader.phase(for: "current-cover") {
            // The replacement is still loading. The previous failure is irrelevant.
        } else {
            XCTFail("旧封面失败不得让正在加载的新封面进入失败状态")
        }

        await oldRequest.value
        await currentRequest.value
        guard case let .success(displayedImage) = loader.phase(for: "current-cover") else {
            return XCTFail("当前封面完成后应正常显示")
        }
        XCTAssertTrue(displayedImage === currentImage.image)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待图片网络事件超时")
    }

    private func makePipeline() -> MediaImagePipeline {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStubURLProtocol.self]
        return MediaImagePipeline(session: URLSession(configuration: configuration))
    }
}

private final class ImageStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedRequestCount = 0
    nonisolated(unsafe) private static var storedStopCount = 0
    nonisolated(unsafe) private static var storedResponseDelay: TimeInterval = 0
    nonisolated(unsafe) private static var storedResponseDelays: [TimeInterval] = []
    nonisolated(unsafe) private static var storedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var storedStatusCode = 200
    private var responseWorkItem: DispatchWorkItem?

    static var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    static var stopCount: Int {
        lock.withLock { storedStopCount }
    }

    static var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    static func reset() {
        lock.withLock {
            storedRequestCount = 0
            storedStopCount = 0
            storedResponseDelay = 0
            storedResponseDelays = []
            storedRequests = []
            storedStatusCode = 200
        }
    }

    static func setResponseDelay(_ delay: TimeInterval) {
        lock.withLock { storedResponseDelay = delay }
    }

    static func setResponseDelays(_ delays: [TimeInterval]) {
        lock.withLock { storedResponseDelays = delays }
    }

    static func setStatusCode(_ statusCode: Int) {
        lock.withLock { storedStatusCode = statusCode }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "images.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self.storedRequestCount += 1
            Self.storedRequests.append(request)
        }
        let delay = Self.lock.withLock {
            if !Self.storedResponseDelays.isEmpty {
                return Self.storedResponseDelays.removeFirst()
            }
            return Self.storedResponseDelay
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.sendResponse()
        }
        responseWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    override func stopLoading() {
        Self.lock.withLock { Self.storedStopCount += 1 }
        responseWorkItem?.cancel()
        responseWorkItem = nil
    }

    private func sendResponse() {
        guard let url = request.url,
              let data = Data(base64Encoded: Self.onePixelPNG),
              let response = HTTPURLResponse(
                url: url,
                statusCode: Self.lock.withLock { Self.storedStatusCode },
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
