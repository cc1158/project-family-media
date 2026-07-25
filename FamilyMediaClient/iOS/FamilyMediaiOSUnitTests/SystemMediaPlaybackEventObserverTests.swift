import AVFAudio
import FamilyMediaCore
import XCTest

@MainActor
final class SystemMediaPlaybackEventObserverTests: XCTestCase {
    func testInterruptionAndRouteLossRequestPauseOnlyWhileObserving() async {
        let observer = SystemMediaPlaybackEventObserver()
        let pauseRequests = expectation(description: "系统事件请求暂停")
        pauseRequests.expectedFulfillmentCount = 2
        var requestCount = 0

        observer.start {
            requestCount += 1
            pauseRequests.fulfill()
        }

        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: session,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: session,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )

        await fulfillment(of: [pauseRequests], timeout: 1)
        XCTAssertEqual(requestCount, 2)

        observer.stop()
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: session,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        await Task.yield()
        XCTAssertEqual(requestCount, 2)
    }
}
