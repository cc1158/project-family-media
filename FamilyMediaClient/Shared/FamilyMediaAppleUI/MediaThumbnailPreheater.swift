import Combine
import FamilyMediaCore
import Foundation

struct MediaThumbnailPreheatCandidate: Sendable {
    let key: MediaImageRequestKey
    let resourceRequest: MediaResourceRequest
}

struct MediaThumbnailPreheatPolicy: Equatable, Sendable {
    static let viewer = MediaThumbnailPreheatPolicy(
        previousItemCount: 2,
        nextItemCount: 4,
        maximumConcurrentRequests: 2
    )

    let previousItemCount: Int
    let nextItemCount: Int
    let maximumConcurrentRequests: Int

    init(
        previousItemCount: Int,
        nextItemCount: Int,
        maximumConcurrentRequests: Int
    ) {
        self.previousItemCount = max(0, previousItemCount)
        self.nextItemCount = max(0, nextItemCount)
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    }

    var orderedOffsets: [Int] {
        guard previousItemCount > 0 || nextItemCount > 0 else { return [] }

        return (1...max(previousItemCount, nextItemCount)).flatMap { distance in
            var offsets: [Int] = []
            if distance <= nextItemCount {
                offsets.append(distance)
            }
            if distance <= previousItemCount {
                offsets.append(-distance)
            }
            return offsets
        }
    }
}

enum MediaThumbnailPreheatPlanner {
    static func candidates(
        items: [MediaItem],
        currentIndex: Int,
        requestAuthorizer: (any MediaResourceRequestAuthorizing)?,
        policy: MediaThumbnailPreheatPolicy = .viewer
    ) -> [MediaThumbnailPreheatCandidate] {
        guard items.indices.contains(currentIndex) else { return [] }

        var seenKeys: Set<MediaImageRequestKey> = []
        return policy.orderedOffsets.compactMap { offset in
            let index = currentIndex + offset
            guard items.indices.contains(index),
                  let url = items[index].readyThumbnailURL,
                  url.scheme != "demo-art"
            else {
                return nil
            }

            let request = requestAuthorizer?.resourceRequest(for: url)
                ?? .unauthenticated(url: url)
            guard let key = MediaImageRequestKey(
                resourceRequest: request,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: CachedRemoteImagePurpose.initialCacheVersion
            ), seenKeys.insert(key).inserted else {
                return nil
            }
            return MediaThumbnailPreheatCandidate(
                key: key,
                resourceRequest: request
            )
        }
    }
}

@MainActor
final class MediaThumbnailPreheater: ObservableObject {
    typealias ImageProvider = @Sendable (MediaResourceRequest) async throws -> Void
    typealias CacheLookup = @Sendable (MediaResourceRequest) -> Bool

    private struct ActiveTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let policy: MediaThumbnailPreheatPolicy
    private let imageProvider: ImageProvider
    private let isCached: CacheLookup
    private var desiredCandidates: [MediaThumbnailPreheatCandidate] = []
    private var activeTasks: [MediaImageRequestKey: ActiveTask] = [:]
    private var attemptedKeys: Set<MediaImageRequestKey> = []

    init(
        policy: MediaThumbnailPreheatPolicy = .viewer,
        imageProvider: @escaping ImageProvider = { request in
            _ = try await MediaImagePipeline.shared.image(
                resourceRequest: request,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: CachedRemoteImagePurpose.initialCacheVersion,
                usesFileBackedDownload: false
            )
        },
        isCached: @escaping CacheLookup = { request in
            MediaImagePipeline.shared.cachedImage(
                resourceRequest: request,
                maximumPixelSize: CachedRemoteImagePurpose.thumbnail.maximumPixelSize,
                cacheVersion: CachedRemoteImagePurpose.initialCacheVersion
            ) != nil
        }
    ) {
        self.policy = policy
        self.imageProvider = imageProvider
        self.isCached = isCached
    }

    func update(
        session: MediaViewerSession,
        requestAuthorizer: (any MediaResourceRequestAuthorizing)?
    ) {
        update(
            items: session.items,
            currentIndex: session.currentIndex,
            requestAuthorizer: requestAuthorizer
        )
    }

    func update(
        items: [MediaItem],
        currentIndex: Int,
        requestAuthorizer: (any MediaResourceRequestAuthorizing)?
    ) {
        desiredCandidates = MediaThumbnailPreheatPlanner.candidates(
            items: items,
            currentIndex: currentIndex,
            requestAuthorizer: requestAuthorizer,
            policy: policy
        )
        let desiredKeys = Set(desiredCandidates.map(\.key))

        let obsoleteKeys = activeTasks.keys.filter { !desiredKeys.contains($0) }
        for key in obsoleteKeys {
            activeTasks[key]?.task.cancel()
            activeTasks.removeValue(forKey: key)
        }
        attemptedKeys = Set(activeTasks.keys)
        schedulePendingRequests()
    }

    func cancel() {
        activeTasks.values.forEach { $0.task.cancel() }
        activeTasks.removeAll()
        desiredCandidates.removeAll()
        attemptedKeys.removeAll()
    }

    private func schedulePendingRequests() {
        while activeTasks.count < policy.maximumConcurrentRequests {
            guard let candidate = desiredCandidates.first(where: {
                !attemptedKeys.contains($0.key) && !isCached($0.resourceRequest)
            }) else {
                return
            }

            attemptedKeys.insert(candidate.key)
            start(candidate)
        }
    }

    private func start(_ candidate: MediaThumbnailPreheatCandidate) {
        let taskID = UUID()
        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await imageProvider(candidate.resourceRequest)
            } catch {
                // Prefetch is best effort. The visible image request owns user-facing errors.
            }
            requestDidFinish(key: candidate.key, taskID: taskID)
        }
        activeTasks[candidate.key] = ActiveTask(id: taskID, task: task)
    }

    private func requestDidFinish(key: MediaImageRequestKey, taskID: UUID) {
        guard activeTasks[key]?.id == taskID else { return }
        activeTasks.removeValue(forKey: key)
        schedulePendingRequests()
    }
}
