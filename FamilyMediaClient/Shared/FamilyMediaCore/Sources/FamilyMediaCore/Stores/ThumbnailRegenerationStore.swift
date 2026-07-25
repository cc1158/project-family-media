import Foundation

@MainActor
public final class ThumbnailRegenerationStore: ObservableObject {
    @Published public private(set) var message: AppMessage?
    @Published public private(set) var isWorking = false
    @Published public private(set) var completedRegenerationCount = 0

    private let mediaService: (any FamilyMediaAdminServicing)?

    public init(mediaService: (any FamilyMediaAdminServicing)?) {
        self.mediaService = mediaService
    }

    public func regenerateThumbnail(
        for item: MediaItem,
        timeOffsetSeconds: Int? = nil
    ) async -> Bool {
        guard !isWorking else { return false }
        guard let mediaService else {
            message = .warning("此媒体来源不支持更新封面")
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await mediaService.regenerateThumbnail(
                mediaID: item.id,
                request: ThumbnailRegenerationRequest(timeOffsetSeconds: timeOffsetSeconds)
            )
            completedRegenerationCount += 1
            message = .success("封面已更新")
            return true
        } catch let error where TaskCancellation.matches(error) {
            return false
        } catch {
            message = .failure(AppErrorMapper.message(for: error))
            return false
        }
    }
}
