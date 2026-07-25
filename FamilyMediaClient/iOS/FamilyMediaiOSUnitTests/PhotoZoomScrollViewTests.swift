import UIKit
import XCTest
@testable import FamilyMediaiOS

@MainActor
final class PhotoZoomScrollViewTests: XCTestCase {
    func testFullImageReplacementKeepsViewportForSameMediaAndAspectRatio() {
        let scrollView = PhotoZoomScrollView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        let zoomDelegate = TestZoomDelegate(zoomView: scrollView.imageView)
        scrollView.delegate = zoomDelegate
        let preview = makeImage(size: CGSize(width: 400, height: 200))
        let full = makeImage(size: CGSize(width: 2_000, height: 1_000))

        scrollView.display(preview, mediaID: "photo", transitionDuration: 0)
        scrollView.layoutIfNeeded()
        scrollView.setZoomScale(2, animated: false)
        scrollView.contentOffset = CGPoint(x: 40, y: 20)
        let previousOffset = scrollView.contentOffset

        scrollView.display(full, mediaID: "photo", transitionDuration: 0)

        XCTAssertEqual(scrollView.zoomScale, 2)
        XCTAssertEqual(scrollView.contentOffset.x, previousOffset.x, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentOffset.y, previousOffset.y, accuracy: 0.001)

        scrollView.display(full, mediaID: "another-photo", transitionDuration: 0)
        XCTAssertEqual(scrollView.zoomScale, 1)
    }

    func testViewportRotationResetsZoomAndEndsPhotoInspection() {
        let scrollView = PhotoZoomScrollView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        let zoomDelegate = TestZoomDelegate(zoomView: scrollView.imageView)
        scrollView.delegate = zoomDelegate
        scrollView.imageView.image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_200, height: 800)
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 800))
        }

        var resetCount = 0
        scrollView.onViewportReset = { resetCount += 1 }
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        XCTAssertEqual(resetCount, 0)

        scrollView.setZoomScale(2.5, animated: false)
        XCTAssertGreaterThan(scrollView.zoomScale, scrollView.minimumZoomScale)

        scrollView.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        XCTAssertEqual(scrollView.zoomScale, scrollView.minimumZoomScale)
        XCTAssertEqual(resetCount, 1)
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class TestZoomDelegate: NSObject, UIScrollViewDelegate {
    private weak var zoomView: UIView?

    init(zoomView: UIView) {
        self.zoomView = zoomView
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomView
    }
}
