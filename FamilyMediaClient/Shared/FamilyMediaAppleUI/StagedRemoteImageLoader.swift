import Combine
import FamilyMediaCore
import UIKit

@MainActor
final class StagedRemoteImageLoader: ObservableObject {
    typealias ImageProvider = @Sendable (
        MediaResourceRequest,
        CachedRemoteImagePurpose,
        Int,
        @escaping MediaImagePipeline.ProgressHandler
    ) async throws -> SendableImage

    @Published private(set) var phase: StagedRemoteImagePhase = .loading

    private let imageProvider: ImageProvider
    private var activeRequestID: String?
    private var activeResourceIdentity: String?

    init(
        imageProvider: @escaping ImageProvider = {
            resourceRequest,
            purpose,
            cacheVersion,
            onProgress in
            try await MediaImagePipeline.shared.image(
                resourceRequest: resourceRequest,
                maximumPixelSize: purpose.maximumPixelSize,
                cacheVersion: cacheVersion,
                usesFileBackedDownload: purpose.usesFileBackedDownload,
                onProgress: onProgress
            )
        }
    ) {
        self.imageProvider = imageProvider
    }

    func load(
        previewRequest: MediaResourceRequest?,
        originalRequest: MediaResourceRequest?,
        cachedPreview: UIImage? = nil,
        originalCacheVersion: Int,
        resourceIdentity: String,
        requestID: String
    ) async {
        let retainedPreview = activeResourceIdentity == resourceIdentity
            ? phase.displayedImage
            : cachedPreview
        activeResourceIdentity = resourceIdentity
        activeRequestID = requestID
        phase = retainedPreview.map { .preview($0, progress: nil) } ?? .loading

        var preview = retainedPreview
        if preview == nil, let previewRequest {
            preview = await loadPreview(previewRequest, requestID: requestID)
            guard !Task.isCancelled else { return }
        }

        guard let originalRequest else {
            guard activeRequestID == requestID else { return }
            phase = preview.map(StagedRemoteImagePhase.full)
                ?? .failed(preview: nil)
            return
        }

        await loadOriginal(
            originalRequest,
            preview: preview,
            cacheVersion: originalCacheVersion,
            requestID: requestID
        )
    }

    func phase(
        for requestID: String,
        resourceIdentity: String? = nil,
        cachedPreview: UIImage? = nil
    ) -> StagedRemoteImagePhase {
        if activeRequestID == requestID {
            return phase
        }
        if let resourceIdentity, activeResourceIdentity == resourceIdentity {
            return phase
        }
        return cachedPreview.map { .preview($0, progress: nil) } ?? .loading
    }

    private func loadPreview(
        _ request: MediaResourceRequest,
        requestID: String
    ) async -> UIImage? {
        do {
            let result = try await imageProvider(
                request,
                .thumbnail,
                CachedRemoteImagePurpose.initialCacheVersion,
                { _ in }
            )
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return nil }
            phase = .preview(result.image, progress: nil)
            return result.image
        } catch {
            return nil
        }
    }

    private func loadOriginal(
        _ request: MediaResourceRequest,
        preview: UIImage?,
        cacheVersion: Int,
        requestID: String
    ) async {
        do {
            let result = try await imageProvider(
                request,
                .photoViewer,
                cacheVersion,
                progressHandler(preview: preview, requestID: requestID)
            )
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            phase = .full(result.image)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID else { return }
            phase = .failed(preview: preview)
        }
    }

    private func progressHandler(
        preview: UIImage?,
        requestID: String
    ) -> MediaImagePipeline.ProgressHandler {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateProgress(progress, preview: preview, requestID: requestID)
            }
        }
    }

    private func updateProgress(
        _ progress: Double?,
        preview: UIImage?,
        requestID: String
    ) {
        guard activeRequestID == requestID, let preview else { return }
        guard case .preview = phase else { return }
        phase = .preview(preview, progress: progress)
    }
}
