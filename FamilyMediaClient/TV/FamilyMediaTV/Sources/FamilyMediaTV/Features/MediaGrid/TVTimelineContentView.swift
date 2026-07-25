import FamilyMediaCore
import SwiftUI

enum TVTimelineFocusID {
    static func year(_ key: String) -> String { "timeline.year.\(key)" }
    static func item(_ id: String) -> String { "timeline.item.\(id)" }
}

struct TVMediaBrowseModeButton: View {
    let selection: MediaBrowseMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(selection.title, systemImage: "square.grid.3x3")
                .padding(.horizontal, 8)
        }
        .accessibilityLabel("展示方式")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("media.browseMode")
    }
}

struct TVMediaTimelineDirectionButton: View {
    let selection: MediaTimelineDirection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(selection.title, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("时间线排序")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("media.timeline.sort")
    }
}

struct TVTimelineContentView: View {
    @ObservedObject var store: MediaTimelineStore
    let mode: MediaBrowseMode
    let columns: [GridItem]
    let source: MediaSourceContext
    let focusedItemID: FocusState<String?>.Binding
    let preferredFocusID: String?
    let focusNamespace: Namespace.ID
    let onSelectItem: (MediaItem) -> Void
    let onSelectYear: (MediaTimelineYear) -> Void

    var body: some View {
        switch store.indexState {
        case .idle, .loading:
            ProgressView("正在整理时间线…")
        case .empty:
            ContentUnavailableView(title: "暂无时间线", message: "当前范围内没有媒体", systemImage: "calendar")
        case .failed(let message):
            ContentUnavailableView(title: "时间线加载失败", message: message, systemImage: "wifi.exclamationmark") {
                Button("重新加载") { Task { await store.loadIndex(force: true) } }
            }
        case .loaded:
            ScrollView {
                if mode == .year { years } else { months }
            }
            .focusScope(focusNamespace)
            .defaultFocus(
                focusedItemID,
                preferredFocusID,
                priority: .userInitiated
            )
        }
    }

    private var years: some View {
        LazyVGrid(columns: columns, spacing: MediaGridMetrics.rowSpacing) {
            ForEach(store.years) { year in
                let focusID = TVTimelineFocusID.year(year.key)
                Button { onSelectYear(year) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let coverURL = year.coverThumbnailURLs.first {
                            AsyncImage(url: coverURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "calendar").font(.system(size: 72))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 210)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            Image(systemName: "calendar")
                                .font(.system(size: 72)).frame(maxWidth: .infinity, minHeight: 170)
                        }
                        Text("\(year.key)年").font(.title2.bold())
                        Text("\(year.count) 项").foregroundStyle(.secondary)
                    }
                    .padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.card)
                .focused(focusedItemID, equals: focusID)
                .prefersDefaultFocus(preferredFocusID == focusID, in: focusNamespace)
                .accessibilityIdentifier("media.timeline.year.\(year.key)")
            }
        }
        .padding(.horizontal, MediaGridMetrics.horizontalPadding)
        .padding(.vertical, MediaGridMetrics.verticalPadding)
    }

    private var months: some View {
        LazyVStack(alignment: .leading, spacing: 46) {
            ForEach(store.months) { month in
                let content = store.content(for: month.key)
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(month.title).font(.title2.bold())
                        Text("\(month.count) 项").foregroundStyle(.secondary)
                    }
                    if content.isLoaded {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVGrid(columns: columns, spacing: MediaGridMetrics.rowSpacing) {
                                ForEach(content.items) { item in
                                    let focusID = TVTimelineFocusID.item(item.id)
                                    Button { onSelectItem(item) } label: {
                                        MediaCardView(
                                            item: item,
                                            isFocused: focusedItemID.wrappedValue == focusID,
                                            resourceRequestAuthorizer: source.resourceRequestAuthorizer
                                        )
                                    }
                                    .buttonStyle(.card)
                                    .focused(focusedItemID, equals: focusID)
                                    .prefersDefaultFocus(preferredFocusID == focusID, in: focusNamespace)
                                    .accessibilityIdentifier("media.timeline.item.\(item.id)")
                                    .task { if store.needsMore(month: month.key, item: item) { await store.loadMore(month: month.key) } }
                                }
                            }
                            if let message = content.errorMessage {
                                Button("继续加载失败：\(message)，重试") { Task { await store.loadMore(month: month.key) } }
                            }
                        }
                    } else if let message = content.errorMessage {
                        Button("加载失败：\(message)，重试") { Task { await store.loadMonth(month.key, force: true) } }
                    } else { ProgressView() }
                }
                .task { await store.loadMonth(month.key) }
            }
        }
        .padding(.horizontal, MediaGridMetrics.horizontalPadding)
        .padding(.vertical, MediaGridMetrics.verticalPadding)
    }
}
