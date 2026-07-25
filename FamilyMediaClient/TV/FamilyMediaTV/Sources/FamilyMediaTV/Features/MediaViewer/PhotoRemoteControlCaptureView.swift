import SwiftUI
import UIKit

enum PhotoRemoteControlAction {
    case select
    case up
    case down
    case left
    case right
    case playPause
    case menu
}

/// Keeps remote focus inside the full-screen photo viewer while its visible
/// controls are hidden. Video input is owned entirely by AVPlayerViewController.
struct PhotoRemoteControlCaptureView: UIViewRepresentable {
    let onAction: (PhotoRemoteControlAction) -> Void

    func makeUIView(context: Context) -> PhotoRemoteControlCaptureUIView {
        let view = PhotoRemoteControlCaptureUIView()
        view.onAction = onAction
        return view
    }

    func updateUIView(_ view: PhotoRemoteControlCaptureUIView, context: Context) {
        view.onAction = onAction
    }
}

final class PhotoRemoteControlCaptureUIView: UIView {
    var onAction: ((PhotoRemoteControlAction) -> Void)?

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "当前照片"
        accessibilityIdentifier = "viewer.photo.surface"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.window?.setNeedsFocusUpdate()
            self?.window?.updateFocusIfNeeded()
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let action = presses.lazy.compactMap({ Self.action(for: $0.type) }).first else {
            super.pressesEnded(presses, with: event)
            return
        }
        onAction?(action)
    }

    private static func action(for pressType: UIPress.PressType) -> PhotoRemoteControlAction? {
        switch pressType {
        case .select: .select
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .playPause: .playPause
        case .menu: .menu
        default: nil
        }
    }
}
