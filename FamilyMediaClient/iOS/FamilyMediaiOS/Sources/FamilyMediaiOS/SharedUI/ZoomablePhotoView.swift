import SwiftUI
import UIKit

struct ZoomablePhotoView: UIViewRepresentable {
    let image: UIImage
    let mediaID: String
    let imageTransitionDuration: TimeInterval
    let onInspectionChanged: (Bool) -> Void
    let onSingleTap: () -> Void
    let isNavigationGestureEnabled: Bool
    let onNavigationDragChanged: (CGSize) -> Void
    let onNavigationDragEnded: (CGSize, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onInspectionChanged: onInspectionChanged,
            onSingleTap: onSingleTap,
            isNavigationGestureEnabled: isNavigationGestureEnabled,
            onNavigationDragChanged: onNavigationDragChanged,
            onNavigationDragEnded: onNavigationDragEnded
        )
    }

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let scrollView = PhotoZoomScrollView()
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator
        scrollView.imageView.isAccessibilityElement = true
        scrollView.imageView.accessibilityLabel = "照片"

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        scrollView.addGestureRecognizer(doubleTap)
        let navigationPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleNavigationPan(_:))
        )
        navigationPan.cancelsTouchesInView = false
        navigationPan.delegate = context.coordinator
        scrollView.addGestureRecognizer(navigationPan)
        context.coordinator.scrollView = scrollView
        context.coordinator.navigationPanGestureRecognizer = navigationPan
        scrollView.onViewportReset = { [weak coordinator = context.coordinator] in
            coordinator?.onInspectionChanged(false)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: PhotoZoomScrollView, context: Context) {
        context.coordinator.onInspectionChanged = onInspectionChanged
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.isNavigationGestureEnabled = isNavigationGestureEnabled
        context.coordinator.onNavigationDragChanged = onNavigationDragChanged
        context.coordinator.onNavigationDragEnded = onNavigationDragEnded
        scrollView.display(
            image,
            mediaID: mediaID,
            transitionDuration: imageTransitionDuration
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: PhotoZoomScrollView?
        weak var navigationPanGestureRecognizer: UIPanGestureRecognizer?
        var onInspectionChanged: (Bool) -> Void
        var onSingleTap: () -> Void
        var isNavigationGestureEnabled: Bool
        var onNavigationDragChanged: (CGSize) -> Void
        var onNavigationDragEnded: (CGSize, CGSize) -> Void
        init(
            onInspectionChanged: @escaping (Bool) -> Void,
            onSingleTap: @escaping () -> Void,
            isNavigationGestureEnabled: Bool,
            onNavigationDragChanged: @escaping (CGSize) -> Void,
            onNavigationDragEnded: @escaping (CGSize, CGSize) -> Void
        ) {
            self.onInspectionChanged = onInspectionChanged
            self.onSingleTap = onSingleTap
            self.isNavigationGestureEnabled = isNavigationGestureEnabled
            self.onNavigationDragChanged = onNavigationDragChanged
            self.onNavigationDragEnded = onNavigationDragEnded
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? PhotoZoomScrollView)?.imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            onInspectionChanged(true)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            onInspectionChanged(scale > scrollView.minimumZoomScale + 0.01)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onInspectionChanged(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            onInspectionChanged(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            onInspectionChanged(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                onInspectionChanged(false)
                return
            }

            let targetScale = min(2.5, scrollView.maximumZoomScale)
            let point = gesture.location(in: scrollView.imageView)
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
            onInspectionChanged(true)
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleNavigationPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.translation(in: view)
            let translation = CGSize(width: point.x, height: point.y)
            switch gesture.state {
            case .changed:
                onNavigationDragChanged(translation)
            case .ended:
                let velocity = gesture.velocity(in: view)
                let projected = CGSize(
                    width: translation.width + velocity.x * 0.2,
                    height: translation.height + velocity.y * 0.2
                )
                onNavigationDragEnded(translation, projected)
            case .cancelled, .failed:
                onNavigationDragEnded(.zero, .zero)
            default:
                break
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical,
                left: horizontal,
                bottom: vertical,
                right: horizontal
            )
        }
    }
}

extension ZoomablePhotoView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let scrollView,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return false }

        let velocity = pan.velocity(in: scrollView)
        return ViewerNavigationGesturePolicy.canBeginPhotoNavigation(
            isEnabled: isNavigationGestureEnabled,
            zoomScale: scrollView.zoomScale,
            minimumZoomScale: scrollView.minimumZoomScale,
            velocity: velocity
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView, let navigationPanGestureRecognizer else { return false }
        let recognizers = [gestureRecognizer, otherGestureRecognizer]
        return recognizers.contains { $0 === navigationPanGestureRecognizer }
            && recognizers.contains { $0 === scrollView.panGestureRecognizer }
    }
}

final class PhotoZoomScrollView: UIScrollView {
    private var lastBoundsSize: CGSize = .zero
    private var representedMediaID: String?
    var onViewportReset: (() -> Void)?

    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
    }

    func display(
        _ image: UIImage,
        mediaID: String,
        transitionDuration: TimeInterval
    ) {
        let isNewMedia = representedMediaID != mediaID
        guard isNewMedia || imageView.image !== image else { return }

        let shouldResetViewport = isNewMedia
            || !hasMatchingAspectRatio(imageView.image, image)
        representedMediaID = mediaID

        guard !shouldResetViewport else {
            setZoomScale(minimumZoomScale, animated: false)
            imageView.image = image
            setNeedsLayout()
            return
        }

        guard transitionDuration > 0 else {
            imageView.image = image
            return
        }
        UIView.transition(
            with: imageView,
            duration: transitionDuration,
            options: [.transitionCrossDissolve, .allowAnimatedContent]
        ) {
            self.imageView.image = image
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let didChangeSize = bounds.size != lastBoundsSize
        if didChangeSize, lastBoundsSize != .zero {
            setZoomScale(minimumZoomScale, animated: false)
            onViewportReset?()
        }
        lastBoundsSize = bounds.size

        if zoomScale == minimumZoomScale {
            let fittedSize = aspectFitSize(for: imageView.image?.size ?? bounds.size)
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
            let horizontal = max(0, (bounds.width - fittedSize.width) / 2)
            let vertical = max(0, (bounds.height - fittedSize.height) / 2)
            contentInset = UIEdgeInsets(
                top: vertical,
                left: horizontal,
                bottom: vertical,
                right: horizontal
            )
        }
    }

    private func aspectFitSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds.size
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func hasMatchingAspectRatio(
        _ existing: UIImage?,
        _ replacement: UIImage
    ) -> Bool {
        guard let existing,
              existing.size.width > 0,
              existing.size.height > 0,
              replacement.size.width > 0,
              replacement.size.height > 0
        else { return false }
        let existingRatio = existing.size.width / existing.size.height
        let replacementRatio = replacement.size.width / replacement.size.height
        return abs(existingRatio - replacementRatio) < 0.01
    }
}
