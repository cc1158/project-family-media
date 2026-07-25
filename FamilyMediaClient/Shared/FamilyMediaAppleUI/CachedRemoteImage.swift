import FamilyMediaCore
import Foundation
import SwiftUI
import UIKit

enum CachedRemoteImagePurpose: Hashable {
    case thumbnail
    case photoViewer

    static let initialCacheVersion = 0

    var maximumPixelSize: Int {
        switch self {
        case .thumbnail: 800
        case .photoViewer: 4_096
        }
    }

    var usesFileBackedDownload: Bool {
        self == .photoViewer
    }
}

enum CachedRemoteImagePhase {
    case empty
    case success(UIImage)
    case failure
}

struct CachedRemoteImage<Content: View>: View {
    let url: URL?
    let purpose: CachedRemoteImagePurpose
    let reloadID: Int
    let requestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let content: (CachedRemoteImagePhase) -> Content

    @StateObject private var loader = CachedRemoteImageLoader()

    init(
        url: URL?,
        purpose: CachedRemoteImagePurpose,
        reloadID: Int = CachedRemoteImagePurpose.initialCacheVersion,
        requestAuthorizer: (any MediaResourceRequestAuthorizing)? = nil,
        @ViewBuilder content: @escaping (CachedRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.purpose = purpose
        self.reloadID = reloadID
        self.requestAuthorizer = requestAuthorizer
        self.content = content
    }

    var body: some View {
        let resourceRequest = resourceRequest
        let requestID = requestID(for: resourceRequest)
        content(loader.phase(for: requestID))
            .task(id: requestID) {
                await loader.load(
                    resourceRequest: resourceRequest,
                    purpose: purpose,
                    cacheVersion: reloadID,
                    requestID: requestID
                )
            }
    }

    private var resourceRequest: MediaResourceRequest? {
        guard let url else { return nil }
        return requestAuthorizer?.resourceRequest(for: url) ?? .unauthenticated(url: url)
    }

    private func requestID(for resourceRequest: MediaResourceRequest?) -> String {
        "\(resourceRequest?.request.url?.absoluteString ?? "none")|\(resourceRequest?.cachePartition ?? "none")|\(purpose.maximumPixelSize)|\(reloadID)"
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    typealias ImageProvider = @Sendable (
        MediaResourceRequest,
        CachedRemoteImagePurpose,
        Int
    ) async throws -> SendableImage

    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false
    @Published private var activeRequestID: String?
    private let imageProvider: ImageProvider

    init(
        imageProvider: @escaping ImageProvider = { resourceRequest, purpose, cacheVersion in
            try await MediaImagePipeline.shared.image(
                resourceRequest: resourceRequest,
                maximumPixelSize: purpose.maximumPixelSize,
                cacheVersion: cacheVersion,
                usesFileBackedDownload: purpose.usesFileBackedDownload
            )
        }
    ) {
        self.imageProvider = imageProvider
    }

    func load(
        resourceRequest: MediaResourceRequest?,
        purpose: CachedRemoteImagePurpose,
        cacheVersion: Int,
        requestID: String
    ) async {
        activeRequestID = requestID
        image = nil
        didFail = false
        guard let resourceRequest else {
            didFail = true
            return
        }

        do {
            let result = try await imageProvider(resourceRequest, purpose, cacheVersion)
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            image = result.image
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID else { return }
            didFail = true
        }
    }

    func load(
        url: URL?,
        purpose: CachedRemoteImagePurpose,
        cacheVersion: Int,
        requestID: String
    ) async {
        await load(
            resourceRequest: url.map(MediaResourceRequest.unauthenticated),
            purpose: purpose,
            cacheVersion: cacheVersion,
            requestID: requestID
        )
    }

    func phase(for requestID: String) -> CachedRemoteImagePhase {
        guard activeRequestID == requestID else { return .empty }
        if let image {
            return .success(image)
        }
        return didFail ? .failure : .empty
    }
}
