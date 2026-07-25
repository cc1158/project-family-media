import FamilyMediaCore
import SwiftUI
import UIKit

struct FamilyServerDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SettingsStore
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVStack(spacing: 18) {
                    FamilyServerCard(store: store, taskController: taskController)
                    FamilyDataMaintenanceCard(store: store, taskController: taskController)
                    if let healthStatus = store.healthStatus {
                        DiagnosticsCard(healthStatus: healthStatus)
                    }
                    if let scanStatus = store.scanStatus {
                        ScanResultCard(scanStatus: scanStatus)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("家庭媒体")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .familyNavigationStyle()
        .task {
            await taskController.runAndWait {
                await store.refreshAndResumeScanMonitoring()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                taskController.cancel()
                return
            }
            taskController.run {
                await store.refreshAndResumeScanMonitoring()
            }
        }
        .onDisappear(perform: taskController.cancel)
    }
}

private struct FamilyDataMaintenanceCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var taskController: ViewTaskController
    @State private var showsClearConfirmation = false

    var body: some View {
        SettingsCard(
            title: "存储与维护",
            subtitle: "重新建立索引和封面",
            systemImage: "externaldrive.fill.badge.minus",
            tint: .orange
        ) {
            Text("清理家映生成的索引、封面和临时文件。NAS 中的原始照片、视频及服务配置不会被删除。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SettingsActionButton(
                title: "清理媒体数据",
                systemImage: "trash",
                prominent: false,
                role: .destructive
            ) {
                showsClearConfirmation = true
            }
            .disabled(store.isWorking)
        }
        .confirmationDialog(
            "清理家映生成的数据？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理并重新扫描", role: .destructive) {
                taskController.run { await store.clearGeneratedData(rescan: true) }
            }
            Button("仅清理", role: .destructive) {
                taskController.run { await store.clearGeneratedData(rescan: false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清理索引、封面缓存和转码临时文件，不会删除 NAS 中的照片或视频。")
        }
    }
}

struct JellyfinDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: JellyfinSettingsStore
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                JellyfinCard(store: store, taskController: taskController)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Jellyfin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .familyNavigationStyle()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                taskController.cancel()
            }
        }
        .onDisappear {
            taskController.cancel()
            store.clearSensitiveInput()
        }
    }
}

private struct FamilyServerCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var taskController: ViewTaskController

    var body: some View {
        SettingsCard(title: "家庭媒体", subtitle: "照片与家庭视频", systemImage: "house.fill", tint: FamilyMediaTheme.accent) {
            SettingsTextField(
                title: "家庭媒体位置",
                placeholder: "http://nas.local:8080",
                text: $store.serverURLText,
                systemImage: "network",
                keyboardType: .URL
            )

            AdaptiveButtonPair {
                SettingsActionButton(title: "保存位置", systemImage: "checkmark", prominent: false) {
                    store.saveServerURL()
                }
            } second: {
                SettingsActionButton(title: "试试能否访问", systemImage: "wifi", prominent: true) {
                    taskController.run { await store.checkConnection() }
                }
            }
            .disabled(store.isWorking)

            Divider().overlay(.white.opacity(0.08))

            AdaptiveButtonPair {
                SettingsActionButton(title: "更新内容", systemImage: "arrow.triangle.2.circlepath", prominent: true) {
                    taskController.run { await store.triggerScan() }
                }
            } second: {
                SettingsActionButton(title: "查看进度", systemImage: "clock.arrow.circlepath", prominent: false) {
                    taskController.run { await store.refreshScanStatus() }
                }
            }
            .disabled(store.isWorking)

            WorkingAndMessage(isWorking: store.isWorking, message: store.message)
        }
    }
}

private struct JellyfinCard: View {
    @ObservedObject var store: JellyfinSettingsStore
    @ObservedObject var taskController: ViewTaskController

    var body: some View {
        SettingsCard(title: "Jellyfin", subtitle: sessionSubtitle, systemImage: "play.tv.fill", tint: FamilyMediaTheme.purple) {
            SettingsTextField(
                title: "Jellyfin 位置",
                placeholder: "http://nas.local:8096",
                text: $store.serverURLText,
                systemImage: "server.rack",
                keyboardType: .URL
            )

            if store.session == nil {
                SettingsTextField(
                    title: "用户名",
                    placeholder: "Jellyfin 用户名",
                    text: $store.username,
                    systemImage: "person.fill"
                )
                SettingsSecureField(
                    title: "密码",
                    placeholder: "Jellyfin 密码",
                    text: $store.password,
                    systemImage: "lock.fill"
                )
            }

            AdaptiveButtonPair {
                SettingsActionButton(title: "试试能否访问", systemImage: "wifi", prominent: false) {
                    taskController.run { await store.checkConnection() }
                }
            } second: {
                if store.session == nil {
                    SettingsActionButton(title: "登录", systemImage: "arrow.right.circle.fill", prominent: true) {
                        taskController.run { await store.login() }
                    }
                    .disabled(store.isWorking)
                } else {
                    SettingsActionButton(title: "退出登录", systemImage: "rectangle.portrait.and.arrow.right", prominent: false, role: .destructive) {
                        taskController.cancel()
                        store.logout()
                    }
                }
            }
            .disabled(store.isWorking)

            if let info = store.serverInfo {
                StatusLine(icon: "checkmark.seal.fill", text: "\(info.ServerName) · \(info.Version)", tint: .green)
            }

            WorkingAndMessage(isWorking: store.isWorking, message: store.message)
        }
    }

    private var sessionSubtitle: String {
        guard let session = store.session else { return "尚未登录" }
        return "已登录 · \(session.username)"
    }
}

private struct AdaptiveButtonPair<First: View, Second: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                first()
                second()
            }
        } else {
            HStack(spacing: 10) {
                first()
                second()
            }
        }
    }
}

struct PlaybackCard: View {
    @Binding var autoplayLimit: Int
    @Binding var photoDurationSeconds: Int

    var body: some View {
        SettingsCard(title: "播放偏好", subtitle: "按你的习惯连续播放", systemImage: "play.fill", tint: .orange) {
            SettingsStepper(
                title: "一次连续播放",
                valueText: "\(autoplayLimit) 个",
                value: $autoplayLimit,
                range: PlaybackSettings.autoplayLimitRange
            )
            Divider().overlay(.white.opacity(0.08))
            SettingsStepper(
                title: "每张照片显示",
                valueText: "\(photoDurationSeconds) 秒",
                value: $photoDurationSeconds,
                range: PlaybackSettings.photoDurationRange
            )
        }
    }
}

private struct DiagnosticsCard: View {
    let healthStatus: HealthStatus

    private var presentation: HealthStatusPresentation {
        HealthStatusPresentation(status: healthStatus)
    }

    var body: some View {
        SettingsCard(title: "访问情况", subtitle: presentation.title, systemImage: "checkmark.shield.fill", tint: .green) {
            ForEach(presentation.rows, id: \.title) { row in
                StatusValueRow(row: row)
            }
        }
    }
}

private struct ScanResultCard: View {
    let scanStatus: ScanStatus

    private var presentation: ScanStatusPresentation {
        ScanStatusPresentation(scanStatus: scanStatus)
    }

    var body: some View {
        SettingsCard(title: "内容更新", subtitle: presentation.status, systemImage: "arrow.triangle.2.circlepath", tint: .orange) {
            ForEach(presentation.rows, id: \.title) { row in
                StatusValueRow(row: row)
            }
            if let error = presentation.error {
                StatusLine(icon: "exclamationmark.triangle.fill", text: error, tint: .red)
            }
        }
    }
}
