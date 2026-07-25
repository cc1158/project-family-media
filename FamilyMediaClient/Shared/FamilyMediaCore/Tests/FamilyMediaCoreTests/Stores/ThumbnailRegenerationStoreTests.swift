import Testing
@testable import FamilyMediaCore

@MainActor
struct ThumbnailRegenerationStoreTests {
    @Test func regeneratesThumbnail() async {
        let service = FakeMediaService()
        service.thumbnailRegenerationResponse = ThumbnailRegenerationResponse(
            id: "photo-1",
            thumbnailStatus: .ready
        )
        let store = ThumbnailRegenerationStore(mediaService: service)
        let item = makeMediaItem(id: "photo-1")

        let didRegenerate = await store.regenerateThumbnail(for: item, timeOffsetSeconds: 12)

        #expect(didRegenerate)
        #expect(service.thumbnailRegenerationRequests.count == 1)
        #expect(service.thumbnailRegenerationRequests[0].mediaID == "photo-1")
        #expect(service.thumbnailRegenerationRequests[0].request.timeOffsetSeconds == 12)
        #expect(store.completedRegenerationCount == 1)
        #expect(store.message == .success("封面已更新"))
    }

    @Test func surfacesFailure() async {
        let service = FakeMediaService()
        service.error = FakeError.failed
        let store = ThumbnailRegenerationStore(mediaService: service)

        let didRegenerate = await store.regenerateThumbnail(for: makeMediaItem(id: "photo-1"))

        #expect(!didRegenerate)
        #expect(store.completedRegenerationCount == 0)
        #expect(store.message == .failure("测试错误"))
    }

    @Test func cancellationDoesNotSurfaceAsFailure() async {
        let service = FakeMediaService()
        service.error = CancellationError()
        let store = ThumbnailRegenerationStore(mediaService: service)

        let didRegenerate = await store.regenerateThumbnail(for: makeMediaItem(id: "photo-1"))

        #expect(!didRegenerate)
        #expect(!store.isWorking)
        #expect(store.completedRegenerationCount == 0)
        #expect(store.message == nil)
    }
}
