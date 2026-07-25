import FamilyMediaCore
import UIKit
import XCTest
@testable import FamilyMediaiOS

final class StagedRemoteImageLoaderTests: XCTestCase {
    @MainActor
    func testPublishesPreviewBeforeFullImage() async throws {
        let preview = SendableImage(makeImage(size: CGSize(width: 20, height: 10)))
        let full = SendableImage(makeImage(size: CGSize(width: 200, height: 100)))
        let loader = StagedRemoteImageLoader { _, purpose, _, onProgress in
            if purpose == .thumbnail {
                return preview
            }
            onProgress(0.25)
            try await Task.sleep(for: .milliseconds(60))
            return full
        }

        let load = Task { @MainActor in
            await loader.load(
                previewRequest: makeResourceRequest("preview.png"),
                originalRequest: makeResourceRequest("full.png"),
                originalCacheVersion: 0,
                resourceIdentity: "photo",
                requestID: "photo|0"
            )
        }
        try await Task.sleep(for: .milliseconds(15))

        guard case let .preview(image, progress) = loader.phase(for: "photo|0") else {
            return XCTFail("原图下载期间应先展示缩略图")
        }
        XCTAssertTrue(image === preview.image)
        XCTAssertEqual(progress, 0.25)
        XCTAssertEqual(loader.phase(for: "photo|0").photoLoadState, .loading)
        XCTAssertTrue(loader.phase(for: "photo|0").displaysPreviewQuality)

        await load.value
        guard case let .full(image) = loader.phase(for: "photo|0") else {
            return XCTFail("原图完成后应替换缩略图")
        }
        XCTAssertTrue(image === full.image)
        XCTAssertEqual(loader.phase(for: "photo|0").photoLoadState, .ready)
        XCTAssertFalse(loader.phase(for: "photo|0").displaysPreviewQuality)
    }

    @MainActor
    func testPreviewNeverMarksPhotoReadyAndFullFailureStopsAutoAdvance() {
        let preview = makeImage(size: CGSize(width: 20, height: 10))

        XCTAssertEqual(
            StagedRemoteImagePhase.preview(preview, progress: 0.5).photoLoadState,
            .loading
        )
        XCTAssertEqual(StagedRemoteImagePhase.full(preview).photoLoadState, .ready)
        XCTAssertEqual(
            StagedRemoteImagePhase.failed(preview: preview).photoLoadState,
            .failed
        )
    }

    @MainActor
    func testCachedPreviewIsAvailableBeforeTheAsynchronousLoadStarts() {
        let preview = makeImage(size: CGSize(width: 20, height: 10))
        let loader = StagedRemoteImageLoader()

        guard case let .preview(image, progress) = loader.phase(
            for: "next|0",
            resourceIdentity: "next",
            cachedPreview: preview
        ) else {
            return XCTFail("已预热缩略图应在新媒体首帧同步显示")
        }
        XCTAssertTrue(image === preview)
        XCTAssertNil(progress)
        XCTAssertEqual(
            loader.phase(
                for: "next|0",
                resourceIdentity: "next",
                cachedPreview: preview
            ).photoLoadState,
            .loading
        )
    }

    @MainActor
    func testFallsBackInBothDirections() async {
        let preview = SendableImage(makeImage(size: CGSize(width: 20, height: 10)))
        let full = SendableImage(makeImage(size: CGSize(width: 200, height: 100)))
        let originalOnly = StagedRemoteImageLoader { _, purpose, _, _ in
            if purpose == .thumbnail {
                throw URLError(.cannotDecodeContentData)
            }
            return full
        }

        await originalOnly.load(
            previewRequest: makeResourceRequest("broken-preview.png"),
            originalRequest: makeResourceRequest("full.png"),
            originalCacheVersion: 0,
            resourceIdentity: "original-only",
            requestID: "original-only|0"
        )
        guard case let .full(image) = originalOnly.phase(for: "original-only|0") else {
            return XCTFail("缩略图失败后仍应直接加载原图")
        }
        XCTAssertTrue(image === full.image)

        let previewOnly = StagedRemoteImageLoader { _, purpose, _, _ in
            if purpose == .thumbnail {
                return preview
            }
            throw URLError(.networkConnectionLost)
        }
        await previewOnly.load(
            previewRequest: makeResourceRequest("preview.png"),
            originalRequest: makeResourceRequest("broken-full.png"),
            originalCacheVersion: 0,
            resourceIdentity: "preview-only",
            requestID: "preview-only|0"
        )
        guard case let .failed(retainedPreview) = previewOnly.phase(for: "preview-only|0") else {
            return XCTFail("原图失败时应保留已经显示的缩略图")
        }
        XCTAssertTrue(retainedPreview === preview.image)
        XCTAssertEqual(previewOnly.phase(for: "preview-only|0").photoLoadState, .failed)
        XCTAssertTrue(previewOnly.phase(for: "preview-only|0").displaysPreviewQuality)

        let totalFailure = StagedRemoteImageLoader { _, _, _, _ in
            throw URLError(.cannotLoadFromNetwork)
        }
        await totalFailure.load(
            previewRequest: makeResourceRequest("broken-preview.png"),
            originalRequest: makeResourceRequest("broken-full.png"),
            originalCacheVersion: 0,
            resourceIdentity: "broken",
            requestID: "broken|0"
        )
        XCTAssertTrue(totalFailure.phase(for: "broken|0").didFailCompletely)
    }

    @MainActor
    func testRetryReloadsOnlyFullImageAndKeepsVisiblePreview() async {
        let preview = SendableImage(makeImage(size: CGSize(width: 20, height: 10)))
        let full = SendableImage(makeImage(size: CGSize(width: 200, height: 100)))
        let calls = ImagePurposeCallRecorder()
        let loader = StagedRemoteImageLoader { _, purpose, cacheVersion, _ in
            await calls.record(purpose)
            if purpose == .thumbnail {
                return preview
            }
            if cacheVersion == 0 {
                throw URLError(.networkConnectionLost)
            }
            return full
        }

        await loader.load(
            previewRequest: makeResourceRequest("preview.png"),
            originalRequest: makeResourceRequest("full.png"),
            originalCacheVersion: 0,
            resourceIdentity: "retry",
            requestID: "retry|0"
        )
        guard case let .failed(retainedPreview) = loader.phase(for: "retry|0") else {
            return XCTFail("首次原图失败后应保留缩略图")
        }
        XCTAssertTrue(retainedPreview === preview.image)
        XCTAssertTrue(
            loader.phase(for: "retry|1", resourceIdentity: "retry").displayedImage
                === preview.image
        )

        await loader.load(
            previewRequest: makeResourceRequest("preview.png"),
            originalRequest: makeResourceRequest("full.png"),
            originalCacheVersion: 1,
            resourceIdentity: "retry",
            requestID: "retry|1"
        )
        guard case let .full(image) = loader.phase(for: "retry|1") else {
            return XCTFail("重试后应显示高清图")
        }
        XCTAssertTrue(image === full.image)
        let thumbnailCalls = await calls.count(for: .thumbnail)
        let fullImageCalls = await calls.count(for: .photoViewer)
        XCTAssertEqual(thumbnailCalls, 1)
        XCTAssertEqual(fullImageCalls, 2)
    }

    @MainActor
    func testIgnoresLateProgressAndResultsFromPreviousPhoto() async throws {
        let oldPreview = SendableImage(makeImage(size: CGSize(width: 20, height: 10)))
        let oldFull = SendableImage(makeImage(size: CGSize(width: 200, height: 100)))
        let currentFull = SendableImage(makeImage(size: CGSize(width: 300, height: 150)))
        let loader = StagedRemoteImageLoader { request, purpose, _, onProgress in
            if purpose == .thumbnail {
                return oldPreview
            }
            if request.request.url?.lastPathComponent == "old-full.png" {
                try? await Task.sleep(for: .milliseconds(70))
                onProgress(0.9)
                return oldFull
            }
            return currentFull
        }
        let oldLoad = Task { @MainActor in
            await loader.load(
                previewRequest: makeResourceRequest("old-preview.png"),
                originalRequest: makeResourceRequest("old-full.png"),
                originalCacheVersion: 0,
                resourceIdentity: "old",
                requestID: "old|0"
            )
        }

        try await Task.sleep(for: .milliseconds(10))
        await loader.load(
            previewRequest: nil,
            originalRequest: makeResourceRequest("current-full.png"),
            originalCacheVersion: 0,
            resourceIdentity: "current",
            requestID: "current|0"
        )
        await oldLoad.value

        guard case let .full(image) = loader.phase(for: "current|0") else {
            return XCTFail("旧照片的迟到事件不得覆盖当前原图")
        }
        XCTAssertTrue(image === currentFull.image)
    }

    private func makeResourceRequest(_ path: String) -> MediaResourceRequest {
        .unauthenticated(url: URL(string: "https://images.example/\(path)")!)
    }

    @MainActor
    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private actor ImagePurposeCallRecorder {
    private var counts: [CachedRemoteImagePurpose: Int] = [:]

    func record(_ purpose: CachedRemoteImagePurpose) {
        counts[purpose, default: 0] += 1
    }

    func count(for purpose: CachedRemoteImagePurpose) -> Int {
        counts[purpose, default: 0]
    }
}
