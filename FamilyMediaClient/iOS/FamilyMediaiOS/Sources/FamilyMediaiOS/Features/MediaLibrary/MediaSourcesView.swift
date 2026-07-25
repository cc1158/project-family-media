import FamilyMediaCore
import SwiftUI

struct MediaSourcesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sourceTaskController = ViewTaskController()
    let mediaSources: MediaSourceRegistry
    let refreshCenter: MediaLibraryRefreshCenter
    @ObservedObject var availabilityStore: MediaSourceAvailabilityStore
    let isDemoMode: Bool
    let demoJellyfinRequiresAuthentication: Bool
    let onOpenSettings: () -> Void
    let onSourceNavigationChanged: (MediaSourceID?) -> Void

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("家映")
                                .font(.largeTitle.bold())
                            Text("把家的时光，放在一起看")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        if !isDemoMode {
                            Button {
                                sourceTaskController.run {
                                    await availabilityStore.refresh()
                                }
                            } label: {
                                if availabilityStore.isRefreshing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(availabilityStore.isRefreshing)
                            .accessibilityLabel("重新检查媒体来源")
                        }
                    }

#if DEBUG
                    if isDemoMode {
                        Label("正在使用演示内容", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.yellow.opacity(0.11), in: Capsule())
                    }
#endif

                    LazyVGrid(columns: sourceColumns, spacing: 16) {
                        if familyAvailability.canBrowse {
                            NavigationLink {
                                FamilyMediaCategoriesView(
                                    source: mediaSources.familyMedia,
                                    refreshCenter: refreshCenter
                                )
                                .onAppear {
                                    onSourceNavigationChanged(.familyMedia)
                                }
                            } label: {
                                familyCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("media.source.family")
                        } else {
                            Button(action: onOpenSettings) {
                                familyCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("media.source.family")
                        }

                        if jellyfinAvailability.canBrowse {
                            NavigationLink {
                                MediaLibraryView(
                                    title: "Jellyfin",
                                    filter: .all,
                                    source: mediaSources.jellyfin,
                                    refreshCenter: refreshCenter
                                )
                                .onAppear {
                                    onSourceNavigationChanged(.jellyfin)
                                }
                            } label: {
                                jellyfinCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("media.source.jellyfin")
                        } else {
                            Button(action: onOpenSettings) {
                                jellyfinCard
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("media.source.jellyfin")
                        }
                    }

                    Text("两个来源保持独立连接，切换不会影响登录状态。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .refreshable {
                guard !isDemoMode else { return }
                await sourceTaskController.runAndWait {
                    await availabilityStore.refresh()
                }
            }
        }
        .navigationTitle("媒体")
        .toolbar(
            horizontalSizeClass == .regular ? .visible : .hidden,
            for: .navigationBar
        )
        .onAppear {
            onSourceNavigationChanged(nil)
        }
        .task {
            guard !isDemoMode else { return }
            await sourceTaskController.runAndWait {
                await availabilityStore.refreshAfterForegroundIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                sourceTaskController.cancel()
            }
        }
        .onDisappear(perform: sourceTaskController.cancel)
    }

    private var familyAvailability: MediaSourceAvailability {
#if DEBUG
        isDemoMode ? .available("演示内容") : availabilityStore.familyMedia
#else
        availabilityStore.familyMedia
#endif
    }

    private var jellyfinAvailability: MediaSourceAvailability {
#if DEBUG
        isDemoMode && !demoJellyfinRequiresAuthentication
            ? .available("演示内容")
            : availabilityStore.jellyfin
#else
        availabilityStore.jellyfin
#endif
    }

    private var sourceColumns: [GridItem] {
        FamilyMediaAdaptiveLayout.overviewColumns(
            for: horizontalSizeClass,
            spacing: 16
        )
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular
            ? FamilyMediaAdaptiveLayout.wideContentMaxWidth
            : FamilyMediaAdaptiveLayout.compactContentMaxWidth
    }

    private var jellyfinCard: some View {
        MediaSourceCard(
            title: "Jellyfin",
            subtitle: jellyfinAvailability == .authenticationRequired
                ? "登录后浏览电影与剧集"
                : "电影、剧集与媒体库",
            systemImage: "play.tv.fill",
            colors: [FamilyMediaTheme.purple, Color.indigo],
            availability: jellyfinAvailability
        )
    }

    private var familyCard: some View {
        MediaSourceCard(
            title: "家庭媒体",
            subtitle: "照片、视频与家庭回忆",
            systemImage: "house.fill",
            colors: [FamilyMediaTheme.accent, Color.blue],
            availability: familyAvailability
        )
    }
}

private struct MediaSourceCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    let availability: MediaSourceAvailability

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 16) {
                        sourceIcon
                        sourceText
                        Spacer(minLength: 0)
                    }

                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 6)
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    sourceIcon
                    sourceText
                }
            } else {
                HStack(spacing: 18) {
                    sourceIcon
                    sourceText
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(
            maxWidth: .infinity,
            minHeight: horizontalSizeClass == .regular ? 210 : 112,
            alignment: .topLeading
        )
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: colors[0].opacity(0.22), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(subtitle)，\(availability.shortTitle)")
        .accessibilityHint(availability.canBrowse ? "双击打开" : "双击前往设置")
        .contentShape(Rectangle())
    }

    private var sourceIcon: some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .frame(width: 60, height: 60)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var sourceText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Label(availability.shortTitle, systemImage: availability.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

}
