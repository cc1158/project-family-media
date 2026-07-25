import FamilyMediaCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    private let buildInfo = ClientBuildInfo.load()
    @StateObject private var store: SettingsStore
    @StateObject private var jellyfinStore: JellyfinSettingsStore
    @AppStorage(PlaybackSettings.autoplayLimitKey) private var autoplayLimit = PlaybackSettings.defaultAutoplayLimit
    @AppStorage(PlaybackSettings.photoDurationKey) private var photoDurationSeconds = PlaybackSettings.defaultPhotoDurationSeconds
    @AppStorage(ClientExperienceSettings.hasCompletedOnboardingKey)
    private var hasCompletedOnboarding = false
#if DEBUG
    @AppStorage("debug_demo_mode") private var isDemoMode = false
    @AppStorage("debug_demo_scenario") private var demoScenario = DemoMediaScenario.content.rawValue
#endif

    init(
        mediaService: any MediaServicing,
        configurationStore: ServerConfigurationStore,
        refreshCenter: MediaLibraryRefreshCenter,
        sourceRefreshCenter: MediaSourceRefreshCenter,
        jellyfinService: JellyfinService,
        jellyfinConfigurationStore: JellyfinConfigurationStore
    ) {
        _store = StateObject(
            wrappedValue: SettingsStore(
                mediaService: mediaService,
                configurationStore: configurationStore,
                refreshCenter: refreshCenter,
                sourceRefreshCenter: sourceRefreshCenter
            )
        )
        _jellyfinStore = StateObject(
            wrappedValue: JellyfinSettingsStore(
                service: jellyfinService,
                configuration: jellyfinConfigurationStore,
                sourceRefreshCenter: sourceRefreshCenter
            )
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    settingsHeader

#if DEBUG
                    DemoModeCard(isEnabled: $isDemoMode, scenario: $demoScenario)
#endif

                    sourceOverview

                    LazyVGrid(columns: overviewColumns, alignment: .leading, spacing: 18) {
                        PlaybackCard(
                            autoplayLimit: $autoplayLimit,
                            photoDurationSeconds: $photoDurationSeconds
                        )

                        VStack(spacing: 14) {
                            diagnosticsLink
                            onboardingButton
                        }
                    }

                    Text(buildInfo.displayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("当前版本，\(buildInfo.displayText)")
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(horizontalSizeClass == .regular ? "设置" : "")
        .toolbar(
            horizontalSizeClass == .regular ? .visible : .hidden,
            for: .navigationBar
        )
        .onAppear {
            repairPlaybackPreferenceBindings()
            jellyfinStore.refreshSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                jellyfinStore.clearSensitiveInput()
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置")
                .font(.largeTitle.bold())
            Text("选择内容来源和喜欢的播放方式")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内容来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: overviewColumns, alignment: .leading, spacing: 14) {
                familySettingsLink
                jellyfinSettingsLink
            }
        }
    }

    private var familySettingsLink: some View {
        NavigationLink {
            FamilyServerDetailView(store: store)
        } label: {
            SettingsOverviewCard(
                title: "家庭媒体",
                subtitle: familyMediaSubtitle,
                systemImage: "house.fill",
                tint: FamilyMediaTheme.accent,
                status: store.connectionStatus == .available ? "可用" : nil
            )
        }
        .buttonStyle(.plain)
    }

    private var jellyfinSettingsLink: some View {
        NavigationLink {
            JellyfinDetailView(store: jellyfinStore)
        } label: {
            SettingsOverviewCard(
                title: "Jellyfin",
                subtitle: jellyfinSubtitle,
                systemImage: "play.tv.fill",
                tint: FamilyMediaTheme.purple,
                status: jellyfinStore.session == nil ? nil : "已登录"
            )
        }
        .buttonStyle(.plain)
    }

    private var diagnosticsLink: some View {
        NavigationLink {
            ClientDiagnosticsView(
                familyStore: store,
                jellyfinStore: jellyfinStore,
                buildInfo: buildInfo
            )
        } label: {
            SettingsOverviewCard(
                title: "帮助与诊断",
                subtitle: "检查连接并复制安全的诊断信息",
                systemImage: "stethoscope",
                tint: .orange,
                status: nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.diagnostics")
    }

    private var onboardingButton: some View {
        Button {
            hasCompletedOnboarding = false
        } label: {
            Label("再次查看使用引导", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityHint("重新打开首次使用说明")
    }

    private var overviewColumns: [GridItem] {
        FamilyMediaAdaptiveLayout.overviewColumns(
            for: horizontalSizeClass,
            spacing: 18
        )
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular
            ? FamilyMediaAdaptiveLayout.settingsWideContentMaxWidth
            : FamilyMediaAdaptiveLayout.compactContentMaxWidth
    }

    private var familyMediaSubtitle: String {
        if store.isWorking { return "正在更新…" }
        if let message = store.message { return message.text }
        return "你的照片和家庭视频"
    }

    private var jellyfinSubtitle: String {
        if jellyfinStore.isWorking { return "正在连接…" }
        if let session = jellyfinStore.session { return "\(session.username) 的媒体库" }
        return "登录后浏览电影与剧集"
    }

    private func repairPlaybackPreferenceBindings() {
        autoplayLimit = PlaybackSettings.normalizedAutoplayLimit(autoplayLimit)
        photoDurationSeconds = PlaybackSettings.normalizedPhotoDurationSeconds(photoDurationSeconds)
    }
}
#if DEBUG
private struct DemoModeCard: View {
    @Binding var isEnabled: Bool
    @Binding var scenario: String

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .frame(width: 46, height: 46)
                        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("演示内容").font(.headline)
                        Text("没有连接服务器时也能体验所有页面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(FamilyMediaTheme.accent)
                }

                if isEnabled {
                    Picker("演示场景", selection: $scenario) {
                        ForEach(DemoMediaScenario.allCases) { scenario in
                            Text(scenario.title).tag(scenario.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}
#endif

private struct SettingsOverviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let status: String?

    var body: some View {
        GlassCard {
            HStack(spacing: 15) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 50, height: 50)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let status {
                            Text(status)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
