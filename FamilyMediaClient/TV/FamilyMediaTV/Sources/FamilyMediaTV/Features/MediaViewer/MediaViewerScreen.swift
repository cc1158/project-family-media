import FamilyMediaCore
import SwiftUI

private enum MediaViewerPanel: Equatable {
    case options
    case information
}

struct MediaViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coordinator: MediaViewerCoordinator
    @StateObject private var chromeController = ViewerChromeController()
    @StateObject private var idleTimerController = PlaybackIdleTimerController()
    @StateObject private var thumbnailTaskController = ViewTaskController()
    @StateObject private var thumbnailPreheater = MediaThumbnailPreheater()
    @State private var presentedPanel: MediaViewerPanel?
    @State private var photoLoadState: MediaPhotoLoadState = .loading
    @AppStorage(PlaybackSettings.autoplayLimitKey) private var autoplayLimit = PlaybackSettings.defaultAutoplayLimit
    @AppStorage(PlaybackSettings.photoDurationKey) private var photoDurationSeconds = PlaybackSettings.defaultPhotoDurationSeconds
    @FocusState private var focusedPhotoControl: PhotoViewerControl?

    let onThumbnailRegenerated: (MediaItem) -> Void
    let onCurrentItemChanged: (MediaItem) -> Void
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let supportsThumbnailRegeneration: Bool

    init(
        items: [MediaItem],
        initialItem: MediaItem,
        source: MediaSourceContext,
        onThumbnailRegenerated: @escaping (MediaItem) -> Void = { _ in },
        onCurrentItemChanged: @escaping (MediaItem) -> Void = { _ in }
    ) {
        self.onThumbnailRegenerated = onThumbnailRegenerated
        self.onCurrentItemChanged = onCurrentItemChanged
        resourceRequestAuthorizer = source.resourceRequestAuthorizer
        supportsThumbnailRegeneration = source.admin != nil
        _coordinator = StateObject(
            wrappedValue: MediaViewerCoordinator(
                items: items,
                initialItem: initialItem,
                thumbnailService: source.admin,
                playbackResolver: source.playbackResolver,
                playbackReporter: source.playbackReporter
            )
        )
        _photoLoadState = State(initialValue: Self.initialPhotoLoadState(initialItem))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if currentItem.kind == .video {
                systemVideoViewer
            } else {
                photoViewer
                    .transition(.opacity)
            }

            if currentItem.kind == .photo,
               !chromeController.isVisible,
               presentedPanel == nil {
                PhotoRemoteControlCaptureView(onAction: handleHiddenPhotoRemoteAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            playbackStatusOverlay

            if currentItem.kind == .video,
               let message = coordinator.regenerationMessage {
                Text(message.text)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(message.tvForegroundStyle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 48)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: coordinator.navigationEvent)
        .onAppear {
            coordinator.start(
                autoplayLimit: effectiveAutoplayLimit,
                photoDurationSeconds: effectivePhotoDurationSeconds,
                onShouldDismiss: { dismiss() },
                onCurrentItemChanged: { item in
                    onCurrentItemChanged(item)
                }
            )
            coordinator.setPhotoReady(photoLoadState == .ready)
            idleTimerController.setPlaybackActive(shouldPreventIdleSleep)
            prepareChromeForCurrentItem()
            updateThumbnailPreheatWindow()
        }
        .onDisappear {
            chromeController.stop()
            thumbnailTaskController.cancel()
            thumbnailPreheater.cancel()
            idleTimerController.release()
            coordinator.stop()
        }
        .onChange(of: shouldPreventIdleSleep) { _, shouldPrevent in
            idleTimerController.setPlaybackActive(shouldPrevent)
        }
        .onChange(of: coordinator.navigationEvent) { _, event in
            presentedPanel = nil
            photoLoadState = Self.initialPhotoLoadState(currentItem)
            coordinator.setPhotoReady(photoLoadState == .ready)
            if currentItem.kind == .photo {
                chromeController.itemDidChange(event: event, context: chromeContext)
                if chromeController.isVisible {
                    focusedPhotoControl = preferredInitialPhotoControl()
                }
            } else {
                chromeController.stop()
                focusedPhotoControl = nil
            }
            updateThumbnailPreheatWindow()
        }
        .onChange(of: coordinator.playbackState) {
            guard currentItem.kind == .photo else { return }
            chromeController.update(context: chromeContext)
        }
        .onChange(of: isVoiceOverEnabled) {
            guard currentItem.kind == .photo else { return }
            if isVoiceOverEnabled {
                showPhotoControls(autoHide: false)
            } else {
                chromeController.update(context: chromeContext)
            }
        }
        .onChange(of: presentedPanel) {
            coordinator.setPhotoAutoAdvanceSuspended(presentedPanel != nil)
            guard currentItem.kind == .photo else { return }
            if presentedPanel == nil {
                focusedPhotoControl = preferredInitialPhotoControl()
                showPhotoControls()
            } else {
                focusedPhotoControl = nil
                showPhotoControls(autoHide: false)
            }
        }
        .onChange(of: chromeController.state) {
            guard currentItem.kind == .photo else { return }
            if chromeController.isVisible {
                if focusedPhotoControl == nil, presentedPanel == nil {
                    focusedPhotoControl = preferredInitialPhotoControl()
                }
            } else {
                focusedPhotoControl = nil
            }
        }
        .alert(
            "已连续播放 \(effectiveAutoplayLimit) 项",
            isPresented: autoplayContinuationAlertBinding
        ) {
            Button("继续播放") {
                coordinator.continueAutoplay()
            }
            Button("返回列表", role: .cancel) {
                coordinator.returnToLibraryAfterAutoplayLimit()
            }
        } message: {
            Text("是否继续播放后面的内容？")
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                coordinator.resumeAfterInterruption()
            case .inactive:
                coordinator.handleInterruption()
            case .background:
                coordinator.handleBackgroundTransition()
            @unknown default:
                coordinator.handleBackgroundTransition()
            }
            if currentItem.kind == .photo {
                chromeController.update(context: chromeContext)
            }
        }
        .accessibilityIdentifier("viewer.screen")
    }

    private var systemVideoViewer: some View {
        TVSystemVideoPlayer(
            snapshot: coordinator.playbackSnapshot,
            item: currentItem,
            information: currentInformation,
            canGoPrevious: coordinator.canGoPrevious,
            canGoNext: coordinator.canGoNext,
            supportsThumbnailRegeneration: supportsThumbnailRegeneration,
            onPrevious: {
                coordinator.goPrevious()
            },
            onNext: {
                coordinator.goNext()
            },
            onRegenerateThumbnail: regenerateThumbnail,
            onDismiss: {
                dismiss()
            }
        )
        .ignoresSafeArea()
        .accessibilityIdentifier("viewer.systemVideoPlayer")
    }

    private var photoViewer: some View {
        ZStack {
            PhotoViewerContent(
                item: currentItem,
                resourceRequestAuthorizer: resourceRequestAuthorizer,
                onLoadStateChanged: handlePhotoLoadStateChanged
            )
            .id(currentItem.id)

            if chromeController.isVisible {
                PhotoViewerControlsOverlay(
                    item: currentItem,
                    photoDateText: currentInformation.compactDateText,
                    canGoPrevious: coordinator.canGoPrevious,
                    canGoNext: coordinator.canGoNext,
                    focusedControl: $focusedPhotoControl,
                    onPrevious: goToPreviousPhoto,
                    onNext: goToNextPhoto,
                    onOptions: togglePhotoOptions
                )
                .disabled(presentedPanel != nil)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if presentedPanel == .options {
                optionsOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if presentedPanel == .information {
                informationOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chromeController.state)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: presentedPanel)
        .onMoveCommand(perform: handlePhotoMoveCommand)
        .onPlayPauseCommand {
            showPhotoControls()
        }
        .onTapGesture {
            showPhotoControls()
        }
        .onExitCommand {
            handlePhotoExit()
        }
    }

    @ViewBuilder
    private var playbackStatusOverlay: some View {
        if currentItem.kind == .video {
            switch coordinator.playbackState {
            case .preparing:
                VStack(spacing: 18) {
                    ProgressView()
                    Text(coordinator.playbackPositionSeconds > 0 ? "正在恢复播放…" : "正在准备播放…")
                }
                .font(.title3)
                .allowsHitTesting(false)
            case .buffering(.transcode):
                Text("Jellyfin 正在转码")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 48)
                    .allowsHitTesting(false)
            case .failed(let failure):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                    Text(failure.message)
                        .multilineTextAlignment(.center)
                    if failure.recovery == .signIn {
                        Text("请退出播放器，然后到设置中重新登录 Jellyfin。")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    HStack(spacing: 18) {
                        if failure.recovery == .retry {
                            Button("重新尝试") {
                                coordinator.retryPlayback()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(FamilyMediaTVTheme.accent)
                        }
                        Button(failure.recovery == .signIn ? "退出播放器" : "返回媒体库") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .foregroundStyle(.orange)
                .padding(40)
                .background(.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            case .buffering:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在缓冲…")
                        .font(.callout)
                }
                .allowsHitTesting(false)
            default:
                EmptyView()
            }
        }
    }

    private var optionsOverlay: some View {
        MediaViewerOptionsPanel(
            supportsThumbnailRegeneration: supportsThumbnailRegeneration,
            isWorking: coordinator.isRegeneratingThumbnail,
            message: coordinator.regenerationMessage,
            onShowInformation: { presentedPanel = .information },
            onRegenerateThumbnail: regenerateThumbnail
        )
    }

    private var informationOverlay: some View {
        MediaInformationPanel(
            presentation: currentInformation,
            onBack: { presentedPanel = .options }
        )
    }

    private var currentItem: MediaItem {
        coordinator.currentItem
    }

    private var currentInformation: MediaInformationPresentation {
        MediaInformationPresentation(item: currentItem)
    }

    private func prepareChromeForCurrentItem() {
        guard currentItem.kind == .photo else {
            chromeController.stop()
            focusedPhotoControl = nil
            return
        }
        chromeController.start(context: chromeContext)
        focusedPhotoControl = preferredInitialPhotoControl()
    }

    private func handlePhotoMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .down:
            showPhotoControls()
        case .up where presentedPanel == .options:
            presentedPanel = nil
        case .left where !chromeController.isVisible && presentedPanel == nil:
            goToPreviousPhoto()
        case .right where !chromeController.isVisible && presentedPanel == nil:
            goToNextPhoto()
        default:
            break
        }
    }

    private func handleHiddenPhotoRemoteAction(_ action: PhotoRemoteControlAction) {
        switch action {
        case .select, .up, .down, .playPause:
            showPhotoControls(autoHide: false)
        case .left:
            goToPreviousPhoto()
        case .right:
            goToNextPhoto()
        case .menu:
            handlePhotoExit()
        }
    }

    private func handlePhotoExit() {
        switch presentedPanel {
        case .information:
            presentedPanel = .options
        case .options:
            presentedPanel = nil
        case nil:
            dismiss()
        }
    }

    private func showPhotoControls(autoHide: Bool = true) {
        chromeController.userDidInteract(context: chromeContext, autoHide: autoHide)
        if focusedPhotoControl == nil {
            focusedPhotoControl = preferredInitialPhotoControl()
        }
    }

    private func goToPreviousPhoto() {
        guard coordinator.goPrevious() else {
            showPhotoControls()
            return
        }
        showPhotoControls()
    }

    private func goToNextPhoto() {
        guard coordinator.goNext() else {
            showPhotoControls()
            return
        }
        showPhotoControls()
    }

    private func updateThumbnailPreheatWindow() {
        thumbnailPreheater.update(
            session: coordinator.session,
            requestAuthorizer: resourceRequestAuthorizer
        )
    }

    private func togglePhotoOptions() {
        presentedPanel = presentedPanel == nil ? .options : nil
    }

    private func regenerateThumbnail() {
        thumbnailTaskController.run {
            let regeneratedItem = currentItem
            let didRegenerate = await coordinator.regenerateThumbnail()
            guard !Task.isCancelled else { return }
            if didRegenerate {
                onThumbnailRegenerated(regeneratedItem)
            }
            if currentItem.kind == .photo {
                showPhotoControls(autoHide: false)
            }
        }
    }

    private func handlePhotoLoadStateChanged(
        itemID: String,
        state: MediaPhotoLoadState
    ) {
        guard currentItem.kind == .photo, currentItem.id == itemID else { return }
        photoLoadState = state
        coordinator.setPhotoReady(state == .ready)
        chromeController.update(context: chromeContext)
    }

    private var chromeContext: ViewerChromeContext {
        ViewerChromeContext(
            itemID: currentItem.id,
            mediaKind: .photo,
            playbackState: .idle,
            isSceneActive: scenePhase == .active,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isScrubbing: false,
            isOverlayPresented: presentedPanel != nil,
            isPhotoInspectionActive: false,
            photoLoadState: photoLoadState,
            isPhotoAutoAdvancePaused: coordinator.isPhotoAutoAdvancePaused
        )
    }

    private func preferredInitialPhotoControl() -> PhotoViewerControl {
        if coordinator.canGoNext {
            return .next
        }
        if coordinator.canGoPrevious {
            return .previous
        }
        return .options
    }

    private var effectiveAutoplayLimit: Int {
        PlaybackSettings.normalizedAutoplayLimit(autoplayLimit)
    }

    private var autoplayContinuationAlertBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isAwaitingAutoplayContinuation },
            set: { isPresented in
                if !isPresented, coordinator.isAwaitingAutoplayContinuation {
                    coordinator.returnToLibraryAfterAutoplayLimit()
                }
            }
        )
    }

    private var effectivePhotoDurationSeconds: Int {
        PlaybackSettings.normalizedPhotoDurationSeconds(photoDurationSeconds)
    }

    private var shouldPreventIdleSleep: Bool {
        MediaViewerWakePolicy.shouldPreventIdleSleep(
            mediaKind: currentItem.kind,
            playbackState: coordinator.playbackState,
            photoLoadState: photoLoadState,
            isSceneActive: scenePhase == .active
        )
    }

    private static func initialPhotoLoadState(_ item: MediaItem) -> MediaPhotoLoadState {
        item.kind == .photo && item.thumbnailURL?.scheme == "demo-art" ? .ready : .loading
    }
}
