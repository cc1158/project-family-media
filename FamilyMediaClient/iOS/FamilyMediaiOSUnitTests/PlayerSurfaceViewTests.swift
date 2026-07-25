import AVFoundation
import XCTest
@testable import FamilyMediaiOS

@MainActor
final class PlayerSurfaceViewTests: XCTestCase {
    func testPlayerLayerOwnsOnlyTheProvidedPlayerSurface() {
        let view = PlayerLayerContainerView()
        let player = AVPlayer()

        view.player = player

        XCTAssertTrue(view.layer is AVPlayerLayer)
        XCTAssertTrue(view.player === player)
        XCTAssertEqual(view.playerLayer?.videoGravity, .resizeAspect)
        XCTAssertEqual(view.accessibilityLabel, "视频画面")

        view.player = nil
        XCTAssertNil(view.player)
    }
}
