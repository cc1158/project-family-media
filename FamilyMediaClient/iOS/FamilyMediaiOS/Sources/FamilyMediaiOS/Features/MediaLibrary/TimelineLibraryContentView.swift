import FamilyMediaCore
import SwiftUI

struct MediaBrowseModePicker: View {
    @Binding var selection: MediaBrowseMode

    var body: some View {
        Picker("展示方式", selection: $selection) {
            ForEach(MediaBrowseMode.allCases, id: \.rawValue) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("media.browseMode")
    }
}

struct MediaTimelineToolbarMenus: View {
    let direction: MediaTimelineDirection
    let years: [MediaTimelineYear]
    let onSelectDirection: (MediaTimelineDirection) -> Void
    let onSelectMonth: (String) -> Void

    var body: some View {
        Menu {
            ForEach(MediaTimelineDirection.allCases, id: \.rawValue) { option in
                Button {
                    onSelectDirection(option)
                } label: {
                    if option == direction {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("时间顺序")
        .accessibilityValue(direction.title)
        .accessibilityIdentifier("media.timeline.sort")

        Menu {
            ForEach(years) { year in
                Menu("\(year.key)年") {
                    ForEach(year.months) { month in
                        Button(month.title) { onSelectMonth(month.key) }
                    }
                }
            }
        } label: {
            Image(systemName: "calendar")
        }
        .accessibilityLabel("快速跳转月份")
        .accessibilityIdentifier("media.timeline.jump")
    }
}

struct TimelineLibraryContentView: View {
    @ObservedObject var store: MediaTimelineStore
    let mode: MediaBrowseMode
    let columns: [GridItem]
    let horizontalPadding: CGFloat
    let source: MediaSourceContext
    @Binding var scrollPositionID: String?
    let onSelectItem: (MediaItem) -> Void
    let onSelectYear: (MediaTimelineYear) -> Void

    var body: some View {
        switch store.indexState {
        case .idle, .loading:
            ProgressView("正在整理时间线…")
        case .empty:
            EmptyStateView(title: "暂无时间线", message: "当前范围内还没有可按日期整理的媒体", systemImage: "calendar.badge.exclamationmark")
        case .failed(let message):
            EmptyStateView(title: "时间线加载失败", message: message) {
                Button("重新加载") { Task { await store.loadIndex(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if mode == .year { yearGrid } else { monthGrid }
        }
    }

    private var yearGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(store.years) { year in
                    Button { onSelectYear(year) } label: {
                        TimelineSummaryCard(title: "\(year.key)年", count: year.count, coverURLs: year.coverThumbnailURLs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("media.timeline.year.\(year.key)")
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
            .padding(.bottom, 96)
        }
    }

    private var monthGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: [.sectionHeaders]) {
                ForEach(store.months) { month in
                    Section {
                        monthBody(month)
                    } header: {
                        HStack {
                            Text(month.title).font(.title3.bold())
                            Spacer()
                            Text("\(month.count) 项").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .id(month.key)
                    }
                    .task { await store.loadMonth(month.key) }
                }
            }
            .padding(.bottom, 96)
        }
        .scrollPosition(id: $scrollPositionID, anchor: .top)
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private func monthBody(_ month: MediaTimelineMonth) -> some View {
        let content = store.content(for: month.key)
        if content.isLoaded {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(content.items) { item in
                        Button { onSelectItem(item) } label: {
                            MediaTileView(item: item, resourceRequestAuthorizer: source.resourceRequestAuthorizer)
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                        .task {
                            if store.needsMore(month: month.key, item: item) { await store.loadMore(month: month.key) }
                        }
                        .accessibilityIdentifier("media.timeline.item.\(item.id)")
                    }
                    if content.isLoading { ProgressView().padding() }
                }
                .scrollTargetLayout()
                if let message = content.errorMessage {
                    monthFailure(message, key: month.key, force: false)
                }
            }
            .padding(.horizontal, horizontalPadding)
        } else if let message = content.errorMessage {
            monthFailure(message, key: month.key, force: true)
                .padding(.horizontal, horizontalPadding)
        } else {
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(minHeight: 140)
        }
    }

    private func monthFailure(_ message: String, key: String, force: Bool) -> some View {
        VStack(spacing: 10) {
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button("重新加载") {
                Task {
                    if force { await store.loadMonth(key, force: true) }
                    else { await store.loadMore(month: key) }
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TimelineSummaryCard: View {
    let title: String
    let count: Int
    let coverURLs: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(Array(coverURLs.prefix(4).enumerated()), id: \.offset) { _, url in
                        CachedRemoteImage(url: url, purpose: .thumbnail) { phase in
                            if case .success(let image) = phase {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else { Color.white.opacity(0.06) }
                        }
                        .frame(height: proxy.size.height / 2)
                        .clipped()
                    }
                }
            }
            .aspectRatio(1.42, contentMode: .fit)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            Text(title).font(.headline)
            Text("\(count) 项").font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(FamilyMediaTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(FamilyMediaTheme.border) }
    }
}
