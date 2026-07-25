import FamilyMediaCore
import SwiftUI

struct JellyfinSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: JellyfinSettingsStore
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        SettingsSection(title: "Jellyfin") {
            Text("连接电影、剧集和其他 Jellyfin 媒体库")
                .foregroundStyle(.secondary)
            TextField("Jellyfin 地址，例如 http://nas-ip:8096", text: $store.serverURLText)
                .frame(maxWidth: 760)

            if store.session == nil {
                TextField("Jellyfin 用户名", text: $store.username)
                    .frame(maxWidth: 760)
                SecureField("Jellyfin 密码", text: $store.password)
                    .frame(maxWidth: 760)
            }

            HStack(spacing: 24) {
                Button("检查连接") {
                    taskController.run { await store.checkConnection() }
                }
                if store.session == nil {
                    Button("登录") {
                        taskController.run { await store.login() }
                    }
                } else {
                    Button("退出登录", role: .destructive) {
                        taskController.cancel()
                        store.logout()
                    }
                }
            }
            .disabled(store.isWorking)

            if let session = store.session {
                Label("已登录：\(session.username)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("尚未登录", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
            if let info = store.serverInfo { Text("\(info.ServerName) · \(info.Version)").foregroundStyle(.secondary) }
            connectionStatusLabel(store.connectionStatus)
            if store.isWorking { ProgressView() }
            if let message = store.message { Text(message.text).foregroundStyle(message.tvForegroundStyle) }
        }
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

    private func connectionStatusLabel(_ status: ClientDiagnosticConnectionStatus) -> some View {
        Label(status.displayText, systemImage: statusSystemImage(status))
            .foregroundStyle(statusColor(status))
    }

    private func statusSystemImage(_ status: ClientDiagnosticConnectionStatus) -> String {
        switch status {
        case .unchecked: "questionmark.circle"
        case .available: "checkmark.circle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    private func statusColor(_ status: ClientDiagnosticConnectionStatus) -> Color {
        switch status {
        case .unchecked: .secondary
        case .available: .green
        case .unavailable: .orange
        }
    }
}
struct ServerSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SettingsStore
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        SettingsSection(title: "家庭媒体") {
            Text("连接家映自带的家庭照片与视频服务")
                .foregroundStyle(.secondary)
            TextField("家庭媒体地址，例如 http://nas-ip:8080", text: $store.serverURLText)
                .frame(maxWidth: 760)

            HStack(spacing: 24) {
                Button("保存地址") {
                    store.saveServerURL()
                }
                Button("检查连接") {
                    taskController.run { await store.checkConnection() }
                }
            }
            .disabled(store.isWorking)

            Label(store.connectionStatus.displayText, systemImage: statusSystemImage)
                .foregroundStyle(statusColor)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                taskController.cancel()
            }
        }
        .onDisappear(perform: taskController.cancel)
    }

    private var statusSystemImage: String {
        switch store.connectionStatus {
        case .unchecked: "questionmark.circle"
        case .available: "checkmark.circle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    private var statusColor: Color {
        switch store.connectionStatus {
        case .unchecked: .secondary
        case .available: .green
        case .unavailable: .orange
        }
    }
}

struct MediaLibrarySettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SettingsStore
    @StateObject private var taskController = ViewTaskController()
    @State private var showsClearConfirmation = false

    var body: some View {
        SettingsSection(title: "更新家庭内容") {
            Text("添加照片或视频后，在这里让家映重新整理内容")
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("更新内容") {
                    taskController.run { await store.triggerScan() }
                }
                Button("查看进度") {
                    taskController.run { await store.refreshScanStatus() }
                }
            }
            .disabled(store.isWorking)

            Divider()

            Text("需要重新建立索引或封面时，可以清理家映生成的数据。NAS 中的原始照片和视频不会被删除。")
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label("清理媒体数据", systemImage: "trash")
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

struct PlaybackSettingsSection: View {
    @Binding var autoplayLimit: Int
    @Binding var photoDurationSeconds: Int

    var body: some View {
        SettingsSection(title: "播放体验") {
            Text("控制自动浏览的节奏，不会改变媒体文件")
                .foregroundStyle(.secondary)
            NumericSettingRow(
                title: "连续自动播放",
                value: $autoplayLimit,
                range: PlaybackSettings.autoplayLimitRange,
                unit: "个"
            )

            NumericSettingRow(
                title: "照片停留",
                value: $photoDurationSeconds,
                range: PlaybackSettings.photoDurationRange,
                unit: "秒"
            )
        }
    }
}

struct HealthStatusView: View {
    let healthStatus: HealthStatus

    private var presentation: HealthStatusPresentation {
        HealthStatusPresentation(status: healthStatus)
    }

    var body: some View {
        SettingsSection(title: "连接诊断") {
            Text(presentation.title)
                .font(.title3.bold())

            ForEach(presentation.rows, id: \.title) { row in
                SettingsStatusRowView(row: row)
            }
        }
    }
}

struct SettingsStatusRowView: View {
    let row: SettingsStatusRow

    var body: some View {
        HStack {
            Text(row.title)
            Spacer()
            Text(row.value)
                .foregroundStyle(row.isHealthy ? .green : .orange)
        }
        .frame(maxWidth: 760)
    }
}
