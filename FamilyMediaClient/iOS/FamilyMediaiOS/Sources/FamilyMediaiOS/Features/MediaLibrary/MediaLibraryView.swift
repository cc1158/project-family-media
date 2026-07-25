import FamilyMediaCore
import SwiftUI

struct MediaLibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browseSession: MediaBrowseSessionController
    @StateObject private var refreshTaskController = ViewTaskController()
    @State private var viewerSelection: ViewerSelection?
    @State private var scrollPositionID: String?
    @State private var lastViewedItemID: String?
    @State private var thumbnailReloadIDs: [String: Int] = [:]
    @State private var isVisible = false
    private let source: MediaSourceContext
    private let refreshCenter: MediaLibraryRefreshCenter
    private let containerID: String?

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
            AppBackground()

            Group {
                if timelineStore.mode == .directory {
                    directoryContent
                } else {
                    TimelineLibraryContentView(
                        store: timelineStore,
                        mode: timelineStore.mode,
                        columns: columns,
                        horizontalPadding: gridHorizontalPadding,
                        source: source,
                        scrollPositionID: $scrollPositionID,
                        onSelectItem: openTimelineItem,
                        onSelectYear: selectYear
                    )
                }
            }

            if timelineStore.mode == .directory {
                VStack(spacing: 10) {
                    if store.isRefreshing {
                        Label("正在更新", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityLabel("正在更新媒体")
                    }

                    if let message = store.refreshMessage {
                        RefreshFailureBanner(message: message.text) {
                            refreshTaskController.run {
                                await browseSession.reloadDirectory(
                                    preservingItemID: scrollPositionID
                                )
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, gridHorizontalPadding)
                .padding(.top, 10)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if timelineStore.isAvailable {
                MediaBrowseModePicker(selection: browseModeBinding)
                    .padding(.horizontal, gridHorizontalPadding)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .familyNavigationStyle()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if timelineStore.mode == .directory, store.isSortingAvailable {
                    sortMenu
                } else if timelineStore.mode != .directory {
                    MediaTimelineToolbarMenus(
                        direction: timelineStore.direction,
                        years: timelineStore.years,
                        onSelectDirection: { direction in
                            refreshTaskController.run {
                                await timelineStore.changeDirection(direction)
                            }
                        },
                        onSelectMonth: { scrollPositionID = $0 }
                    )
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isRefreshing)
        .task {
            await browseSession.prepare(preservingItemID: scrollPositionID)
        }
        .onChange(of: refreshCenter.generation) {
            guard isVisible, viewerSelection == nil else { return }
            refreshTaskController.run {
                await browseSession.refresh(preservingItemID: scrollPositionID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                refreshTaskController.cancel()
                return
            }
            guard isVisible, viewerSelection == nil else { return }
            refreshTaskController.run {
                await browseSession.refreshAfterForeground(
                    preservingItemID: scrollPositionID
                )
            }
        }
        .fullScreenCover(isPresented: isViewerPresented, onDismiss: refreshAfterViewerDismiss) {
            if let selection = viewerSelection {
                MediaViewerScreen(
                    items: selection.items,
                    initialItem: selection.item,
                    source: source,
                    onThumbnailRegenerated: refreshAfterThumbnailRegeneration,
                    onCurrentItemChanged: updateViewerPosition
                )
            }
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            refreshTaskController.cancel()
        }
    }

    @ViewBuilder
    private var directoryContent: some View {
        switch store.state {
        case .idle, .loading:
            MediaLibrarySkeletonView(
                columns: columns,
                horizontalPadding: gridHorizontalPadding
            )
        case .empty:
            EmptyStateView(
                title: store.title,
                message: emptyStateMessage,
                systemImage: containerID == nil
                    ? "rectangle.stack.badge.minus"
                    : "folder.badge.minus"
            )
        case .failed(let message):
            EmptyStateView(title: "加载失败", message: message) {
                Button("重新加载") {
                    refreshTaskController.run {
                        await browseSession.reloadDirectory(
                            preservingItemID: scrollPositionID
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(FamilyMediaTheme.accent)
            }
        case .loaded(let items):
            ScrollView {
                VStack(spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(items) { item in
                            if item.isContainer {
                                NavigationLink {
                                    MediaLibraryView(
                                        title: item.name,
                                        filter: store.filter,
                                        source: source,
                                        refreshCenter: refreshCenter,
                                        containerID: item.containerID
                                    )
                                    .onAppear {
                                        scrollPositionID = item.id
                                    }
                                } label: {
                                    MediaTileView(
                                        item: item,
                                        resourceRequestAuthorizer: source.resourceRequestAuthorizer,
                                        containerLabel: containerTypeLabel,
                                        thumbnailReloadID: thumbnailReloadID(for: item)
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier(mediaItemIdentifier(item))
                                .task(id: allowsPagination) {
                                    guard allowsPagination else { return }
                                    await store.loadMoreIfNeeded(currentItem: item)
                                }
                            } else {
                                Button {
                                    scrollPositionID = item.id
                                    lastViewedItemID = item.id
                                    viewerSelection = ViewerSelection(
                                        item: item,
                                        items: items.filter { !$0.isContainer }
                                    )
                                } label: {
                                    MediaTileView(
                                        item: item,
                                        resourceRequestAuthorizer: source.resourceRequestAuthorizer,
                                        thumbnailReloadID: thumbnailReloadID(for: item)
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier(mediaItemIdentifier(item))
                                .task(id: allowsPagination) {
                                    guard allowsPagination else { return }
                                    await store.loadMoreIfNeeded(currentItem: item)
                                }
                            }
                        }

                        if store.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .scrollTargetLayout()

                    if let message = store.loadMoreMessage {
                        LoadMoreFailureView(message: message.text) {
                            refreshTaskController.run {
                                await store.retryLoadMore()
                            }
                        }
                    }
                }
                .padding(.horizontal, gridHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollPosition(id: $scrollPositionID, anchor: .top)
            .refreshable {
                await browseSession.reloadDirectory(
                    preservingItemID: scrollPositionID
                )
            }
        }
    }

    private var browseModeBinding: Binding<MediaBrowseMode> {
        Binding(
            get: { timelineStore.mode },
            set: { mode in
                scrollPositionID = nil
                refreshTaskController.run {
                    await browseSession.changeMode(
                        to: mode,
                        preservingItemID: scrollPositionID
                    )
                }
            })
    }

    private func openTimelineItem(_ item: MediaItem) {
        scrollPositionID = item.id
        lastViewedItemID = item.id
        viewerSelection = ViewerSelection(item: item, items: timelineStore.flattenedItems)
    }

    private func selectYear(_ year: MediaTimelineYear) {
        refreshTaskController.run {
            await browseSession.changeMode(
                to: .month,
                preservingItemID: scrollPositionID
            )
            scrollPositionID = year.months.first?.key
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(store.availableSortOptions, id: \.rawValue) { option in
                Button {
                    changeSort(to: option)
                } label: {
                    if option == store.selectedSort {
                        Label(option.title(for: source.id), systemImage: "checkmark")
                    } else {
                        Label(
                            option.title(for: source.id),
                            systemImage: option.directionSystemImage
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.bold))

                Text(store.selectedSort.compactTitle(for: source.id))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(FamilyMediaTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FamilyMediaTheme.accent.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(FamilyMediaTheme.accent.opacity(0.22), lineWidth: 1)
            }
        }
        .accessibilityLabel("排序")
        .accessibilityValue(store.selectedSort.title(for: source.id))
        .accessibilityIdentifier("media.sort.menu")
    }

    private func changeSort(to option: MediaSortOption) {
        guard option != store.selectedSort else { return }
        scrollPositionID = nil
        refreshTaskController.run {
            await store.changeSort(to: option)
            guard case .loaded(let items) = store.state else { return }
            scrollPositionID = items.first?.id
        }
    }

    private func refreshAfterThumbnailRegeneration(_ item: MediaItem) {
        thumbnailReloadIDs[item.id, default: 0] &+= 1
        refreshTaskController.run {
            await browseSession.reloadDirectory(preservingItemID: item.id)
        }
    }

    private func refreshAfterViewerDismiss() {
        let targetItemID = lastViewedItemID
        refreshTaskController.run {
            await Task.yield()
            scrollPositionID = targetItemID
            await browseSession.refreshAfterViewerDismiss(
                preservingItemID: targetItemID
            )
            guard !Task.isCancelled else { return }
            scrollPositionID = targetItemID
        }
    }

    private var store: MediaLibraryStore { browseSession.library }

    private var timelineStore: MediaTimelineStore { browseSession.timeline }

    private func thumbnailReloadID(for item: MediaItem) -> Int {
        thumbnailReloadIDs[item.id, default: 0]
    }

    private func updateViewerPosition(_ item: MediaItem) {
        lastViewedItemID = item.id
    }

    /// Presentation is intentionally boolean rather than item-identified. The
    /// viewer owns current-item navigation after it opens, so moving to the next
    /// item must not be interpreted by SwiftUI as a different full-screen cover.
    private var isViewerPresented: Binding<Bool> {
        Binding(
            get: { viewerSelection != nil },
            set: { isPresented in
                if !isPresented {
                    viewerSelection = nil
                }
            }
        )
    }

    private func mediaItemIdentifier(_ item: MediaItem) -> String {
        "media.item.\(item.id)"
    }

    private var containerTypeLabel: String {
        source.containerTypeLabel(containerID: containerID)
    }

    private var allowsPagination: Bool {
        isVisible && scenePhase == .active && viewerSelection == nil
    }

    private var columns: [GridItem] {
        FamilyMediaAdaptiveLayout.mediaColumns(
            for: horizontalSizeClass,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var gridHorizontalPadding: CGFloat {
        FamilyMediaAdaptiveLayout.mediaGridHorizontalPadding(
            for: horizontalSizeClass
        )
    }

    private var emptyStateMessage: String {
        containerID == nil
            ? "这个媒体库暂时没有内容"
            : "这个文件夹暂时没有内容"
    }
}

private struct RefreshFailureBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Text("更新失败：\(message)")
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("重试", action: onRetry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(FamilyMediaTheme.accent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct LoadMoreFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("重试", action: onRetry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(FamilyMediaTheme.accent)
        }
        .padding(14)
        .background(FamilyMediaTheme.surface, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct MediaLibrarySkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let columns: [GridItem]
    let horizontalPadding: CGFloat
    @State private var isDimmed = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.white.opacity(0.10))
                            .aspectRatio(1.42, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.10))
                            .frame(height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.07))
                            .frame(width: 62, height: 9)
                    }
                    .padding(8)
                    .background(FamilyMediaTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
        }
        .opacity(isDimmed ? 0.45 : 0.90)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
        .accessibilityLabel("正在加载媒体")
    }
}

private struct ViewerSelection {
    let item: MediaItem
    let items: [MediaItem]
}
