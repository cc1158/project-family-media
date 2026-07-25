import FamilyMediaCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let buildInfo = ClientBuildInfo.load()
    @StateObject private var store: SettingsStore
    @StateObject private var jellyfinStore: JellyfinSettingsStore
    @AppStorage(PlaybackSettings.autoplayLimitKey) private var autoplayLimit = PlaybackSettings.defaultAutoplayLimit
    @AppStorage(PlaybackSettings.photoDurationKey) private var photoDurationSeconds = PlaybackSettings.defaultPhotoDurationSeconds
    @AppStorage(ClientExperienceSettings.hasCompletedOnboardingKey)
    private var hasCompletedOnboarding = false

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
            TVAppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("设置")
                            .font(.largeTitle.bold())
                        Text("连接家里的媒体服务，调整适合你的播放方式")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    ServerSettingsSection(store: store)
                    JellyfinSettingsSection(store: jellyfinStore)
                    MediaLibrarySettingsSection(store: store)
                    PlaybackSettingsSection(
                        autoplayLimit: $autoplayLimit,
                        photoDurationSeconds: $photoDurationSeconds
                    )

                    NavigationLink {
                        TVClientDiagnosticsView(
                            familyStore: store,
                            jellyfinStore: jellyfinStore,
                            buildInfo: buildInfo
                        )
                    } label: {
                        Label("帮助与诊断", systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FamilyMediaTVTheme.accent)

                    if store.isWorking {
                        ProgressView()
                    }

                    if let message = store.message {
                        Text(message.text)
                            .font(.title3)
                            .foregroundStyle(message.tvForegroundStyle)
                    }

                    if let healthStatus = store.healthStatus {
                        HealthStatusView(healthStatus: healthStatus)
                    }

                    if let scanStatus = store.scanStatus {
                        ScanStatusView(scanStatus: scanStatus)
                    }

                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("再次查看使用引导", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Text(buildInfo.displayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(80)
            }
        }
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

    private func repairPlaybackPreferenceBindings() {
        autoplayLimit = PlaybackSettings.normalizedAutoplayLimit(autoplayLimit)
        photoDurationSeconds = PlaybackSettings.normalizedPhotoDurationSeconds(photoDurationSeconds)
    }
}
