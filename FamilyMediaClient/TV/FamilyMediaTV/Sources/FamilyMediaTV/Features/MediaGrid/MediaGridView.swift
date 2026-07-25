import FamilyMediaCore
import SwiftUI

struct MediaGridView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browseSession: MediaBrowseSessionController
    @StateObject private var refreshTaskController = ViewTaskController()
    @StateObject private var focusRestoreTaskController = ViewTaskController()
    @State private var viewerSelection: ViewerSelection?
    @State private var lastViewedItemID: String?
    @State private var lastFocusedItemID: String?
    @State private var thumbnailReloadIDs: [String: Int] = [:]
    @State private var isVisible = false
    @State private var presentedControlPicker: TVMediaControlPicker?
    @FocusState private var focusedItemID: String?
    @FocusState private var isSortButtonFocused: Bool
    @Namespace private var mediaGridFocusNamespace
    private let source: MediaSourceContext
    private let refreshCenter: MediaLibraryRefreshCenter
    private let containerID: String?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: MediaGridMetrics.columnMinWidth,
                maximum: MediaGridMetrics.columnMaxWidth
            ),
            spacing: MediaGridMetrics.columnSpacing
        )
    ]

    init(
        title: String,
        filter: MediaFilter,
        source: MediaSourceContext,
        refreshCenter: MediaLibraryRefreshCenter,
        containerID: String? = nil
    ) {
        self.source = source
        self.refreshCenter = refreshCenter
        self.containerID = containerID
        _browseSession = StateObject(
            wrappedValue: MediaBrowseSessionController(
                title: title,
                filter: filter,
                source: source,
                refreshCenter: refreshCenter,
                containerID: containerID
            )
        )
    }

    var body: some View {
        ZStack {
            TVAppBackground()

            Group {
                if timelineStore.mode == .directory {
                    directoryContent
                } else {
                    TVTimelineContentView(
                        store: timelineStore,
                        mode: timelineStore.mode,
                        columns: columns,
                        source: source,
                        focusedItemID: $focusedItemID,
                        preferredFocusID: timelinePreferredFocusID,
                        focusNamespace: mediaGridFocusNamespace,
                        onSelectItem: openTimelineItem,
                        onSelectYear: { year in
                            prepareForTimelineFocusChange()
                            refreshTaskController.run {
                                await browseSession.changeMode(
                                    to: .month,
                                    preservingItemID: focusedItemID
                                )
                            }
                        }
                    )
                }
            }

            if timelineStore.mode == .directory {
                VStack(spacing: 14) {
                    if store.isRefreshing {
                        Label("正在更新媒体", systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    if let message = store.refreshMessage {
                        HStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                            Text("更新失败：\(message.text)").font(.callout.weight(.semibold)).lineLimit(2)
                            Button("重试") {
                                refreshTaskController.run {
                                    await browseSession.reloadDirectory(
                                        preservingItemID: focusedItemID
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 22)
            }
        }
        .navigationTitle(store.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if timelineStore.isAvailable {
                    TVMediaBrowseModeButton(
                        selection: timelineStore.mode,
                        action: { presentedControlPicker = .browseMode }
                    )
                }
                if timelineStore.mode == .directory, store.isSortingAvailable {
                    sortButton
                } else if timelineStore.mode != .directory {
                    TVMediaTimelineDirectionButton(
                        selection: timelineStore.direction,
                        action: { presentedControlPicker = .timelineDirection }
                    )
                }
            }
        }
        .confirmationDialog(
            controlPickerTitle,
            isPresented: isControlPickerPresented,
            titleVisibility: .visible
        ) {
            controlPickerActions
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isRefreshing)
        .task {
            await browseSession.prepare(preservingItemID: focusedItemID)
        }
        .onChange(of: refreshCenter.generation) {
            guard isVisible, viewerSelection == nil else { return }
            refreshTaskController.run {
                await browseSession.refresh(preservingItemID: focusedItemID)
            }
        }
        .onChange(of: focusedItemID) { _, itemID in if let itemID { lastFocusedItemID = itemID } }
        .onChange(of: timelinePreferredFocusID) { _, focusID in
            restoreTimelineFocusIfNeeded(focusID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                refreshTaskController.cancel()
                return
            }
            guard isVisible, viewerSelection == nil, timelineStore.mode == .directory else { return }
            refreshTaskController.run {
                await browseSession.refreshAfterForeground(
                    preservingItemID: focusedItemID
                )
            }
        }
        .fullScreenCover(item: $viewerSelection, onDismiss: viewerDidDismiss) { selection in
            MediaViewerScreen(
                items: selection.items,
                initialItem: selection.item,
                source: source,
                onThumbnailRegenerated: refreshAfterThumbnailRegeneration,
                onCurrentItemChanged: updateFocusedItem
            )
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            refreshTaskController.cancel()
            focusRestoreTaskController.cancel()
        }
    }

    @ViewBuilder
    private var directoryContent: some View {
        switch store.state {
        case .idle, .loading:
            MediaGridSkeletonView(columns: columns)
        case .empty:
            ContentUnavailableView(
                title: store.title,
                message: emptyStateMessage,
                systemImage: containerID == nil
                    ? "rectangle.stack.badge.minus"
                    : "folder.badge.minus"
            )
        case .failed(let message):
            ContentUnavailableView(
                title: "无法加载媒体",
                message: message,
                systemImage: "wifi.exclamationmark"
            ) {
                Button("重新加载") {
                    refreshTaskController.run {
                        await browseSession.reloadDirectory(
                            preservingItemID: focusedItemID
                        )
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(FamilyMediaTVTheme.accent)
        case .loaded(let items):
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: MediaGridMetrics.rowSpacing) {
                    ForEach(items) { item in
                        if item.isContainer {
                            NavigationLink {
                                MediaGridView(
                                    title: item.name,
                                    filter: store.filter,
                                    source: source,
                                    refreshCenter: refreshCenter,
                                    containerID: item.containerID
                                )
                            } label: {
                                MediaCardView(
                                    item: item,
                                    isFocused: focusedItemID == item.id,
                                    resourceRequestAuthorizer: source.resourceRequestAuthorizer,
                                    containerLabel: containerTypeLabel,
                                    thumbnailReloadID: thumbnailReloadID(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedItemID, equals: item.id)
                            .prefersDefaultFocus(
                                lastFocusedItemID == item.id,
                                in: mediaGridFocusNamespace
                            )
                            .accessibilityIdentifier(mediaItemIdentifier(item))
                            .task(id: allowsPagination) {
                                guard allowsPagination else { return }
                                await store.loadMoreIfNeeded(currentItem: item)
                            }
                        } else {
                            Button {
                                lastViewedItemID = item.id
                                lastFocusedItemID = item.id
                                focusedItemID = item.id
                                viewerSelection = ViewerSelection(
                                    item: item, items: items.filter { !$0.isContainer })
                            } label: {
                                MediaCardView(
                                    item: item,
                                    isFocused: focusedItemID == item.id,
                                    resourceRequestAuthorizer: source.resourceRequestAuthorizer,
                                    thumbnailReloadID: thumbnailReloadID(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedItemID, equals: item.id)
                            .prefersDefaultFocus(
                                lastFocusedItemID == item.id,
                                in: mediaGridFocusNamespace
                            )
                            .accessibilityIdentifier(mediaItemIdentifier(item))
                            .task(id: allowsPagination) {
                                guard allowsPagination else { return }
                                await store.loadMoreIfNeeded(currentItem: item)
                            }
                        }
                    }

                    if store.isLoadingMore {
                        ProgressView()
                            .frame(width: MediaArtworkMetrics.width, height: MediaArtworkMetrics.height)
                            .accessibilityLabel("正在加载更多媒体")
                    }

                    if let message = store.loadMoreMessage {
                        loadMoreMessageView(message)
                    }
                }
                .padding(.horizontal, MediaGridMetrics.horizontalPadding)
                .padding(.vertical, MediaGridMetrics.verticalPadding)
            }
            .focusScope(mediaGridFocusNamespace)
            .defaultFocus(
                $focusedItemID,
                lastFocusedItemID ?? items.first?.id,
                priority: .userInitiated
            )
        }
    }

    private func changeBrowseMode(_ mode: MediaBrowseMode) {
        prepareForTimelineFocusChange()
        refreshTaskController.run {
            await browseSession.changeMode(
                to: mode,
                preservingItemID: focusedItemID
            )
        }
    }

    private func openTimelineItem(_ item: MediaItem) {
        lastViewedItemID = item.id
        let focusID = TVTimelineFocusID.item(item.id)
        lastFocusedItemID = focusID
        focusedItemID = focusID
        viewerSelection = ViewerSelection(item: item, items: timelineStore.flattenedItems)
    }

    private var sortButton: some View {
        Button {
            presentedControlPicker = .directorySort
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 18, weight: .bold))

                Text(store.selectedSort.compactTitle(for: source.id))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSortButtonFocused ? Color.black : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                isSortButtonFocused ? Color.white : Color.white.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSortButtonFocused
                            ? FamilyMediaTVTheme.accent
                            : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isSortButtonFocused && !reduceMotion ? 1.04 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: isSortButtonFocused
            )
        }
        .buttonStyle(.plain)
        .focused($isSortButtonFocused)
        .accessibilityLabel("排序")
        .accessibilityValue(store.selectedSort.title(for: source.id))
        .accessibilityIdentifier("media.sort.menu")
    }

    private var isControlPickerPresented: Binding<Bool> {
        Binding(
            get: { presentedControlPicker != nil },
            set: { isPresented in
                if !isPresented { presentedControlPicker = nil }
            }
        )
    }

    private var controlPickerTitle: String {
        switch presentedControlPicker {
        case .browseMode:
            "选择展示方式"
        case .directorySort:
            "选择排序方式"
        case .timelineDirection:
            "选择时间线顺序"
        case nil:
            "媒体浏览选项"
        }
    }

    @ViewBuilder
    private var controlPickerActions: some View {
        switch presentedControlPicker {
        case .browseMode:
            ForEach(MediaBrowseMode.allCases, id: \.rawValue) { mode in
                let isSelected = mode == timelineStore.mode
                Button {
                    presentedControlPicker = nil
                    changeBrowseMode(mode)
                } label: {
                    Label(
                        controlPickerOptionTitle(mode.title, isSelected: isSelected),
                        systemImage: isSelected ? "checkmark" : "rectangle.grid.2x2"
                    )
                }
                .accessibilityValue(isSelected ? "当前选择" : "")
                .accessibilityIdentifier("media.browseMode.\(mode.rawValue)")
            }
        case .directorySort:
            ForEach(store.availableSortOptions, id: \.rawValue) { option in
                let isSelected = option == store.selectedSort
                Button {
                    presentedControlPicker = nil
                    changeSort(to: option)
                } label: {
                    Label(
                        controlPickerOptionTitle(
                            option.title(for: source.id),
                            isSelected: isSelected
                        ),
                        systemImage: isSelected ? "checkmark" : option.directionSystemImage
                    )
                }
                .accessibilityValue(isSelected ? "当前选择" : "")
                .accessibilityIdentifier("media.sort.option.\(option.rawValue)")
            }
        case .timelineDirection:
            ForEach(MediaTimelineDirection.allCases, id: \.rawValue) { direction in
                let isSelected = direction == timelineStore.direction
                Button {
                    presentedControlPicker = nil
                    refreshTaskController.run {
                        await timelineStore.changeDirection(direction)
                    }
                } label: {
                    Label(
                        controlPickerOptionTitle(direction.title, isSelected: isSelected),
                        systemImage: isSelected ? "checkmark" : "arrow.up.arrow.down"
                    )
                }
                .accessibilityValue(isSelected ? "当前选择" : "")
                .accessibilityIdentifier("media.timeline.sort.\(direction.rawValue)")
            }
        case nil:
            EmptyView()
        }
    }

    // tvOS confirmation dialogs only render an action's text and discard the
    // Label image. Keep the selection mark in the title so it remains visible.
    private func controlPickerOptionTitle(_ title: String, isSelected: Bool) -> String {
        isSelected ? "✓ \(title)" : title
    }

    private func changeSort(to option: MediaSortOption) {
        guard option != store.selectedSort else { return }
        lastFocusedItemID = nil
        focusedItemID = nil
        refreshTaskController.run {
            await store.changeSort(to: option)
            guard case .loaded(let items) = store.state, let first = items.first else { return }
            lastFocusedItemID = first.id
            resetFocus(in: mediaGridFocusNamespace)
        }
    }

    private func refreshAfterThumbnailRegeneration(_ item: MediaItem) {
        thumbnailReloadIDs[item.id, default: 0] &+= 1
        refreshTaskController.run {
            await browseSession.reloadDirectory(preservingItemID: item.id)
        }
    }

    private func thumbnailReloadID(for item: MediaItem) -> Int {
        thumbnailReloadIDs[item.id, default: 0]
    }

    private func updateFocusedItem(_ item: MediaItem) {
        lastViewedItemID = item.id
        let focusID = focusID(forItemID: item.id)
        lastFocusedItemID = focusID
        focusedItemID = focusID
    }

    private func restoreLastViewedFocus() {
        guard let lastViewedItemID else { return }
        lastFocusedItemID = focusID(forItemID: lastViewedItemID)
        focusedItemID = nil
        focusRestoreTaskController.run {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard viewerSelection == nil else { return }
            resetFocus(in: mediaGridFocusNamespace)
        }
    }

    private var timelinePreferredFocusID: String? {
        switch timelineStore.mode {
        case .directory:
            nil
        case .year:
            timelineStore.years.first.map { TVTimelineFocusID.year($0.key) }
        case .month:
            timelineStore.flattenedItems.first.map { TVTimelineFocusID.item($0.id) }
        }
    }

    private func prepareForTimelineFocusChange() {
        lastFocusedItemID = nil
        focusedItemID = nil
    }

    private func restoreTimelineFocusIfNeeded(_ focusID: String?) {
        guard timelineStore.mode != .directory,
              viewerSelection == nil,
              presentedControlPicker == nil,
              let focusID,
              focusedItemID == nil
        else { return }

        lastFocusedItemID = focusID
        focusRestoreTaskController.run {
            await Task.yield()
            guard viewerSelection == nil, presentedControlPicker == nil else { return }
            resetFocus(in: mediaGridFocusNamespace)
        }
    }

    private func focusID(forItemID itemID: String) -> String {
        timelineStore.mode == .directory
            ? itemID
            : TVTimelineFocusID.item(itemID)
    }

    private func viewerDidDismiss() {
        restoreLastViewedFocus()
        refreshTaskController.run {
            await browseSession.refreshAfterViewerDismiss(
                preservingItemID: lastViewedItemID
            )
        }
    }

    private var store: MediaLibraryStore { browseSession.library }

    private var timelineStore: MediaTimelineStore { browseSession.timeline }

    private func mediaItemIdentifier(_ item: MediaItem) -> String {
        "media.item.\(item.id)"
    }

    private var containerTypeLabel: String {
        source.containerTypeLabel(containerID: containerID)
    }

    private var allowsPagination: Bool {
        isVisible && scenePhase == .active && viewerSelection == nil
    }

    private var emptyStateMessage: String {
        containerID == nil
            ? "这个媒体库暂时没有内容"
            : "这个文件夹暂时没有内容"
    }

    private func loadMoreMessageView(_ message: AppMessage) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message.text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(message.tvForegroundStyle)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("重试") {
                refreshTaskController.run {
                    await store.retryLoadMore()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(width: MediaArtworkMetrics.width, height: MediaArtworkMetrics.height)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MediaArtworkMetrics.cornerRadius))
    }
}

private enum TVMediaControlPicker {
    case browseMode
    case directorySort
    case timelineDirection
}

private struct MediaGridSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let columns: [GridItem]
    @State private var isDimmed = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: MediaGridMetrics.rowSpacing) {
                ForEach(0..<10, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: MediaArtworkMetrics.cornerRadius)
                            .fill(.white.opacity(0.11))
                            .frame(width: MediaArtworkMetrics.width, height: MediaArtworkMetrics.height)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.10))
                            .frame(width: 220, height: 18)
                    }
                }
            }
            .padding(.horizontal, MediaGridMetrics.horizontalPadding)
            .padding(.vertical, MediaGridMetrics.verticalPadding)
        }
        .opacity(isDimmed ? 0.42 : 0.88)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
        .accessibilityLabel("正在加载媒体")
    }
}

private struct ViewerSelection: Identifiable {
    let item: MediaItem
    let items: [MediaItem]

    var id: String {
        item.id
    }
}
