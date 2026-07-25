import FamilyMediaCore
import SwiftUI

struct StagedRemoteImage<Content: View>: View {
    let previewURL: URL?
    let originalURL: URL?
    let originalReloadID: Int
    let requestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let content: (StagedRemoteImagePhase) -> Content

    @StateObject private var loader = StagedRemoteImageLoader()

    init(
        previewURL: URL?,
        originalURL: URL?,
        originalReloadID: Int = CachedRemoteImagePurpose.initialCacheVersion,
        requestAuthorizer: (any MediaResourceRequestAuthorizing)? = nil,
        @ViewBuilder content: @escaping (StagedRemoteImagePhase) -> Content
    ) {
        self.previewURL = previewURL
        self.originalURL = originalURL
        self.originalReloadID = originalReloadID
        self.requestAuthorizer = requestAuthorizer
        self.content = content
    }

    var body: some View {
        let previewRequest = resourceRequest(for: previewURL)
        let originalRequest = resourceRequest(for: originalURL)
        let identity = resourceIdentity(
            previewRequest: previewRequest,
            originalRequest: originalRequest
        )
        let requestID = "\(identity)|\(originalReloadID)"
        let cachedPreview = previewRequest.flatMap {
            MediaImagePipeline.shared.cachedImage(
                resourceRequest: $0,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: CachedRemoteImagePurpose.initialCacheVersion
            )?.image
        }

        content(
            loader.phase(
                for: requestID,
                resourceIdentity: identity,
                cachedPreview: cachedPreview
            )
        )
            .task(id: requestID) {
                await loader.load(
                    previewRequest: previewRequest,
                    originalRequest: originalRequest,
                    cachedPreview: cachedPreview,
                    originalCacheVersion: originalReloadID,
                    resourceIdentity: identity,
                    requestID: requestID
                )
            }
    }

    private func resourceRequest(for url: URL?) -> MediaResourceRequest? {
        guard let url else { return nil }
        return requestAuthorizer?.resourceRequest(for: url)
            ?? .unauthenticated(url: url)
    }

    private func resourceIdentity(
        previewRequest: MediaResourceRequest?,
        originalRequest: MediaResourceRequest?
    ) -> String {
        [
            previewRequest?.request.url?.absoluteString ?? "no-preview",
            previewRequest?.cachePartition ?? "no-preview-partition",
            originalRequest?.request.url?.absoluteString ?? "no-original",
            originalRequest?.cachePartition ?? "no-original-partition"
        ].joined(separator: "|")
    }
}
