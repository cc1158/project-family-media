import FamilyMediaCore
import Foundation

enum ViewerChromeState: Equatable {
    case visible
    case hidden
    case automaticTransition
    case persistent

    var isVisible: Bool {
        switch self {
        case .visible, .persistent:
            true
        case .hidden, .automaticTransition:
            false
        }
    }
}

struct ViewerChromeContext: Equatable {
    let itemID: String
    let mediaKind: MediaKind
    let playbackState: MediaPlaybackState
    let isSceneActive: Bool
    let isVoiceOverEnabled: Bool
    let isScrubbing: Bool
    let isOverlayPresented: Bool
    let isPhotoInspectionActive: Bool
    let photoLoadState: MediaPhotoLoadState
    let isPhotoAutoAdvancePaused: Bool

    var shouldAutoHide: Bool {
        isSceneActive && ViewerChromePolicy.shouldAutoHide(
            mediaKind: mediaKind,
            playbackState: playbackState,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isScrubbing: isScrubbing,
            isOverlayPresented: isOverlayPresented,
            isPhotoInspectionActive: isPhotoInspectionActive,
            isPhotoReady: photoLoadState == .ready,
            isPhotoAutoAdvancePaused: isPhotoAutoAdvancePaused
        )
    }

    var hasBlockingInteraction: Bool {
        isVoiceOverEnabled
            || isScrubbing
            || isOverlayPresented
            || (mediaKind == .photo
                && (isPhotoInspectionActive || isPhotoAutoAdvancePaused))
    }

    var hasFailure: Bool {
        if case .failed = playbackState {
            return true
        }
        return mediaKind == .photo && photoLoadState == .failed
    }
}

/// Owns viewer chrome visibility and its timer. Screens only translate platform
/// input into controller events; media callbacks never write visibility directly.
@MainActor
final class ViewerChromeController: ObservableObject {
    @Published private(set) var state: ViewerChromeState = .visible

    var isVisible: Bool { state.isVisible }

    private let scheduler: any DelayedActionScheduling
    private var currentItemID: String?
    private var timerGeneration: UInt64 = 0

    init(scheduler: any DelayedActionScheduling = DelayedActionScheduler()) {
        self.scheduler = scheduler
    }

    func start(context: ViewerChromeContext) {
        currentItemID = context.itemID
        show(context: context)
    }

    func stop() {
        cancelAutoHide()
        currentItemID = nil
    }

    func itemDidChange(
        event: MediaViewerNavigationEvent,
        context: ViewerChromeContext
    ) {
        guard event.itemID == context.itemID else { return }
        currentItemID = event.itemID
        cancelAutoHide()

        switch event.origin {
        case .automatic:
            state = .automaticTransition
        case .initial, .manual:
            show(context: context)
        }
    }

    /// Applies an asynchronous media or environment update. The item identity
    /// prevents a late callback from the previous photo/player changing chrome.
    func update(context: ViewerChromeContext) {
        guard context.itemID == currentItemID else { return }

        if context.hasFailure {
            makePersistent()
            return
        }

        if state == .automaticTransition {
            if didFinishAutomaticTransition(context) {
                state = .hidden
            }
            return
        }

        if context.hasBlockingInteraction || requiresVisibleChrome(context) {
            makePersistent()
        } else if state.isVisible {
            show(context: context)
        }
    }

    func userDidInteract(context: ViewerChromeContext, autoHide: Bool = true) {
        guard context.itemID == currentItemID else { return }
        if autoHide {
            show(context: context)
        } else {
            makePersistent()
        }
    }

    func userDidHide() {
        guard currentItemID != nil else { return }
        cancelAutoHide()
        state = .hidden
    }

    private func show(context: ViewerChromeContext) {
        cancelAutoHide()
        guard context.shouldAutoHide else {
            state = .persistent
            return
        }

        state = .visible
        scheduleAutoHide(for: context.itemID)
    }

    private func makePersistent() {
        cancelAutoHide()
        state = .persistent
    }

    private func scheduleAutoHide(for itemID: String) {
        let generation = timerGeneration
        scheduler.schedule(afterSeconds: ViewerChromePolicy.autoHideSeconds) { [weak self] in
            guard let self,
                  self.timerGeneration == generation,
                  self.currentItemID == itemID
            else { return }
            self.state = .hidden
        }
    }

    private func cancelAutoHide() {
        timerGeneration &+= 1
        scheduler.cancel()
    }

    private func didFinishAutomaticTransition(_ context: ViewerChromeContext) -> Bool {
        switch context.mediaKind {
        case .photo:
            return context.photoLoadState == .ready
        case .video:
            if case .playing = context.playbackState {
                return true
            }
            return false
        }
    }

    private func requiresVisibleChrome(_ context: ViewerChromeContext) -> Bool {
        switch context.mediaKind {
        case .photo:
            return context.photoLoadState != .ready
        case .video:
            if case .playing = context.playbackState {
                return false
            }
            return true
        }
    }
}
