import FamilyMediaCore
import SwiftUI

struct MediaViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var coordinator: MediaViewerCoordinator
    @StateObject private var idleTimerController = PlaybackIdleTimerController()
    @StateObject private var chromeController = ViewerChromeController()
    @StateObject private var thumbnailTaskController = ViewTaskController()
    @StateObject private var thumbnailPreheater = MediaThumbnailPreheater()
    @State private var isOptionsPresented = false
    @State private var scrubberSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var isPhotoInspectionActive = false
    @State private var photoLoadState: MediaPhotoLoadState = .loading
    @State private var pagingState = ViewerPagingPresentationState()
    @State private var dismissState = ViewerDismissPresentationState()
    @AppStorage(PlaybackSettings.autoplayLimitKey) private var autoplayLimit = PlaybackSettings.defaultAutoplayLimit
    @AppStorage(PlaybackSettings.photoDurationKey) private var photoDurationSeconds = PlaybackSettings.defaultPhotoDurationSeconds

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
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(dismissState.backgroundOpacity)
                    .ignoresSafeArea()

                interactionSurface
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("viewer.currentItem.\(currentItem.id)")
                    .accessibilityValue(currentItem.displayTitle)

                playbackStatusOverlay
                    .opacity(viewerOverlayOpacity)

                if let message = coordinator.regenerationMessage {
                    Text(message.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(message.overlayForegroundStyle)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, chromeController.isVisible ? 88 : 24)
                        .opacity(viewerOverlayOpacity)
                }

                if isChromePresented {
                    controlsBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(currentItem.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.white)
                    .accessibilityLabel("关闭播放器")
                    .accessibilityIdentifier("viewer.close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isOptionsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .tint(.white)
                    .accessibilityLabel("媒体选项")
                    .accessibilityIdentifier("viewer.options")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(isChromePresented ? .visible : .hidden, for: .navigationBar)
        }
        .presentationBackground(.clear)
        .statusBarHidden(!isChromePresented)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: chromeController.state
        )
        .onAppear {
            coordinator.setMuted(true)
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
            chromeController.start(context: chromeContext)
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
            _ = pagingState.resetForItemChange()
            dismissState.reset()
            isOptionsPresented = false
            scrubberSeconds = 0
            isScrubbing = false
            isPhotoInspectionActive = false
            photoLoadState = Self.initialPhotoLoadState(currentItem)
            coordinator.setPhotoReady(photoLoadState == .ready)
            chromeController.itemDidChange(event: event, context: chromeContext)
            updateThumbnailPreheatWindow()
        }
        .onChange(of: coordinator.playbackState) {
            chromeController.update(context: chromeContext)
        }
        .onChange(of: coordinator.playbackPositionSeconds) {
            guard !isScrubbing else { return }
            scrubberSeconds = coordinator.playbackPositionSeconds
        }
        .onChange(of: isScrubbing) {
            if isScrubbing {
                chromeController.userDidInteract(context: chromeContext, autoHide: false)
            } else {
                chromeController.update(context: chromeContext)
            }
        }
        .onChange(of: isOptionsPresented) {
            updatePhotoInteractionSuspension()
            if isOptionsPresented {
                chromeController.userDidInteract(context: chromeContext, autoHide: false)
            } else {
                chromeController.update(context: chromeContext)
            }
        }
        .onChange(of: isVoiceOverEnabled) {
            if isVoiceOverEnabled {
                chromeController.userDidInteract(context: chromeContext, autoHide: false)
            } else {
                chromeController.update(context: chromeContext)
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                coordinator.resumeAfterInterruption()
                chromeController.update(context: chromeContext)
            case .inactive:
                coordinator.handleInterruption()
                chromeController.update(context: chromeContext)
            case .background:
                coordinator.handleBackgroundTransition()
                chromeController.update(context: chromeContext)
            @unknown default:
                coordinator.handleBackgroundTransition()
                chromeController.update(context: chromeContext)
            }
        }
        .sheet(isPresented: $isOptionsPresented) {
            MediaViewerOptionsSheet(
                information: currentInformation,
                supportsThumbnailRegeneration: supportsThumbnailRegeneration,
                isWorking: coordinator.isRegeneratingThumbnail,
                message: coordinator.regenerationMessage,
                onRegenerateThumbnail: regenerateThumbnail
            )
            .presentationDetents([.medium])
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
    }

    private var interactionSurface: some View {
        MediaViewerInteractionSurface(
            item: currentItem,
            previewItem: previewItem,
            pagingState: pagingState,
            dismissState: dismissState,
            player: coordinator.player,
            resourceRequestAuthorizer: resourceRequestAuthorizer,
            reduceMotion: reduceMotion,
            isNavigationGestureEnabled: isNavigationGestureEnabled,
            onPhotoInspectionChanged: handlePhotoInspectionChanged,
            onPhotoLoadStateChanged: handlePhotoLoadStateChanged,
            onToggleChrome: toggleChrome,
            onNavigationDragChanged: handleNavigationDragChanged,
            onNavigationDragEnded: { translation, projectedTranslation, viewportSize in
                handleNavigationDragEnded(
                    translation,
                    projectedTranslation: projectedTranslation,
                    viewportSize: viewportSize
                )
            }
        )
    }

    private var controlsBar: some View {
        MediaViewerControlsBar(
            mediaKind: currentItem.kind,
            photoDateText: currentInformation.compactDateText,
            timeline: coordinator.playbackTimeline,
            playbackTitle: currentPlaybackControlTitle,
            playbackSystemImage: currentPlaybackControlSystemImage,
            isMuted: coordinator.isMuted,
            canGoPrevious: canGoPrevious,
            canTogglePlayback: canToggleCurrentPlayback,
            canGoNext: canGoNext,
            isCompactHeight: isCompactHeight,
            scrubberSeconds: $scrubberSeconds,
            isScrubbing: $isScrubbing,
            onSeek: coordinator.seek,
            onToggleMute: toggleMute,
            onPrevious: goPrevious,
            onTogglePlayback: togglePlayback,
            onNext: goNext
        )
    }

    @ViewBuilder
    private var playbackStatusOverlay: some View {
        MediaViewerStatusOverlay(
            playbackState: coordinator.playbackState,
            playbackPositionSeconds: coordinator.playbackPositionSeconds,
            onRetry: coordinator.retryPlayback,
            onDismiss: dismiss.callAsFunction
        )
    }

    private var currentItem: MediaItem {
        coordinator.currentItem
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

    private var currentInformation: MediaInformationPresentation {
        MediaInformationPresentation(item: currentItem)
    }

    private var canGoPrevious: Bool {
        coordinator.canGoPrevious
    }

    private var canGoNext: Bool {
        coordinator.canGoNext
    }

    private var currentPlaybackControlTitle: String {
        if currentItem.kind == .photo {
            return coordinator.isPhotoAutoAdvancePaused ? "播放照片" : "暂停照片"
        }
        return coordinator.isPlaying ? "暂停" : "播放"
    }

    private var currentPlaybackControlSystemImage: String {
        if currentItem.kind == .photo {
            return coordinator.isPhotoAutoAdvancePaused ? "play.fill" : "pause.fill"
        }
        return coordinator.isPlaying ? "pause.fill" : "play.fill"
    }

    private var canToggleCurrentPlayback: Bool {
        currentItem.kind == .photo || coordinator.playbackState.canTogglePlayback
    }

    private func goPrevious() {
        coordinator.goPrevious()
        chromeController.userDidInteract(context: chromeContext)
    }

    private func goNext() {
        coordinator.goNext()
        chromeController.userDidInteract(context: chromeContext)
    }

    private func updateThumbnailPreheatWindow() {
        thumbnailPreheater.update(
            session: coordinator.session,
            requestAuthorizer: resourceRequestAuthorizer
        )
    }

    private func togglePlayback() {
        if currentItem.kind == .photo {
            coordinator.togglePhotoAutoAdvance()
            chromeController.userDidInteract(
                context: chromeContext,
                autoHide: !coordinator.isPhotoAutoAdvancePaused
            )
        } else {
            coordinator.togglePlayback()
            chromeController.userDidInteract(context: chromeContext)
        }
    }

    private func toggleMute() {
        coordinator.toggleMuted()
        chromeController.userDidInteract(context: chromeContext)
    }

    private var isNavigationGestureEnabled: Bool {
        ViewerNavigationGesturePolicy.isEnabled(
            isVoiceOverEnabled: isVoiceOverEnabled,
            isPhotoInspectionActive: isPhotoInspectionActive,
            isScrubbing: isScrubbing,
            isOverlayPresented: isOptionsPresented,
            isTransitioning: pagingState.isTransitioning || dismissState.isTransitioning
        )
    }

    private var previewItem: MediaItem? {
        switch pagingState.previewDirection {
        case .previous: coordinator.previousItem
        case .next: coordinator.nextItem
        case nil: nil
        }
    }

    private func handleNavigationDragChanged(
        _ translation: CGSize,
        viewportSize: CGSize
    ) {
        guard !pagingState.isTransitioning, !dismissState.isTransitioning else { return }
        if dismissState.isInteracting
            || (pagingState.offset == 0
                && ViewerDismissGesturePolicy.hasDownwardIntent(translation)) {
            pagingState.resetVisualState()
            dismissState.update(
                translation: translation,
                viewportHeight: viewportSize.height
            )
            return
        }

        pagingState.update(
            translation: translation,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
    }

    private func handleNavigationDragEnded(
        _ translation: CGSize,
        projectedTranslation: CGSize,
        viewportSize: CGSize
    ) {
        guard !pagingState.isTransitioning, !dismissState.isTransitioning else { return }
        if dismissState.isInteracting {
            completeOrCancelDismiss(
                translation: translation,
                projectedTranslation: projectedTranslation,
                viewportHeight: viewportSize.height
            )
            return
        }

        guard let direction = ViewerPagingGesturePolicy.decision(
            translation: translation,
            projectedTranslation: projectedTranslation,
            viewportWidth: viewportSize.width,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        ) else {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.18)) {
                pagingState.resetVisualState()
            }
            return
        }

        if reduceMotion {
            pagingState.beginTransition(
                direction: direction,
                width: viewportSize.width,
                movesContent: false
            )
            withAnimation(.easeOut(duration: 0.12)) {
                pagingState.setContentVisible(false)
            } completion: {
                completePaging(direction)
                withAnimation(.easeIn(duration: 0.12)) {
                    pagingState.setContentVisible(true)
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                pagingState.beginTransition(
                    direction: direction,
                    width: viewportSize.width
                )
            } completion: {
                completePaging(direction)
            }
        }
    }

    private func completeOrCancelDismiss(
        translation: CGSize,
        projectedTranslation: CGSize,
        viewportHeight: CGFloat
    ) {
        guard ViewerDismissGesturePolicy.shouldDismiss(
            translation: translation,
            projectedTranslation: projectedTranslation,
            viewportHeight: viewportHeight
        ) else {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.16)) {
                dismissState.reset()
            }
            return
        }

        chromeController.stop()
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.2)) {
            dismissState.beginDismiss(
                viewportHeight: viewportHeight,
                reduceMotion: reduceMotion
            )
        } completion: {
            dismiss()
        }
    }

    private func completePaging(_ direction: ViewerPagingDirection) {
        pagingState.prepareForItemChange()
        let didChange: Bool
        switch direction {
        case .previous:
            didChange = coordinator.goPrevious()
        case .next:
            didChange = coordinator.goNext()
        }
        if !didChange {
            pagingState.cancelPreparedItemChange()
        }
        pagingState.resetVisualState()
    }

    private func regenerateThumbnail() {
        chromeController.userDidInteract(context: chromeContext, autoHide: false)
        thumbnailTaskController.run {
            let regeneratedItem = currentItem
            let didRegenerate = await coordinator.regenerateThumbnail()
            guard !Task.isCancelled else { return }
            if didRegenerate {
                onThumbnailRegenerated(regeneratedItem)
            }
        }
    }

    private func handlePhotoInspectionChanged(itemID: String, isActive: Bool) {
        guard currentItem.id == itemID else { return }
        isPhotoInspectionActive = isActive
        updatePhotoInteractionSuspension()
        if isActive {
            chromeController.userDidHide()
        } else {
            chromeController.update(context: chromeContext)
        }
    }

    private func updatePhotoInteractionSuspension() {
        coordinator.setPhotoAutoAdvanceSuspended(isPhotoInspectionActive || isOptionsPresented)
    }

    private func handlePhotoLoadStateChanged(itemID: String, state: MediaPhotoLoadState) {
        guard currentItem.kind == .photo, currentItem.id == itemID else { return }
        photoLoadState = state
        coordinator.setPhotoReady(state == .ready)
        chromeController.update(context: chromeContext)
    }

    private func toggleChrome() {
        if chromeController.isVisible {
            guard !isVoiceOverEnabled,
                  !isScrubbing,
                  !isOptionsPresented
            else {
                return
            }
            chromeController.userDidHide()
        } else {
            chromeController.userDidInteract(context: chromeContext)
        }
    }

    private var chromeContext: ViewerChromeContext {
        ViewerChromeContext(
            itemID: currentItem.id,
            mediaKind: currentItem.kind,
            playbackState: coordinator.playbackState,
            isSceneActive: scenePhase == .active,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isScrubbing: isScrubbing,
            isOverlayPresented: isOptionsPresented,
            isPhotoInspectionActive: isPhotoInspectionActive,
            photoLoadState: photoLoadState,
            isPhotoAutoAdvancePaused: coordinator.isPhotoAutoAdvancePaused
        )
    }

    private var effectiveAutoplayLimit: Int {
        PlaybackSettings.normalizedAutoplayLimit(autoplayLimit)
    }

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var isChromePresented: Bool {
        chromeController.isVisible && !dismissState.isInteracting && !dismissState.isTransitioning
    }

    private var viewerOverlayOpacity: Double {
        dismissState.isInteracting || dismissState.isTransitioning
            ? 0
            : dismissState.contentOpacity
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
