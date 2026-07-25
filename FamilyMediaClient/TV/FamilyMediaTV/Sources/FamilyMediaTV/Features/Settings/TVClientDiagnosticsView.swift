import FamilyMediaCore
import SwiftUI
import UIKit

struct TVClientDiagnosticsView: View {
    @ObservedObject var familyStore: SettingsStore
    @ObservedObject var jellyfinStore: JellyfinSettingsStore
    let buildInfo: ClientBuildInfo

    @State private var isChecking = false
    @State private var diagnosticEvents: [ClientDiagnosticEvent] = []
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        ZStack {
            TVAppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("帮助与诊断")
                            .font(.largeTitle.bold())
                        Text("检查连接；需要协助时可以拍下诊断信息")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 30) {
                        SettingsSection(title: "连接状态") {
                            statusRow("家庭媒体", status: familyStatus)
                            statusRow(
                                "Jellyfin",
                                status: jellyfinStatus,
                                detail: jellyfinStore.session == nil ? "未登录" : "已登录"
                            )
                            Button(isChecking ? "正在检查…" : "重新检查两个来源") {
                                taskController.run { await checkConnections() }
                            }
                            .disabled(isChecking)
                        }

                        SettingsSection(title: "安全诊断信息") {
                            Text(report.text)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineSpacing(5)
                            Label(
                                "不包含密码、登录凭证、媒体名称或设备标识",
                                systemImage: "lock.shield.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(.green)
                        }
                    }

                    SettingsSection(title: "连接不上时") {
                        Text("1. 确认 Apple TV 与 NAS 在同一个家庭网络")
                        Text("2. 在 Apple TV 系统设置中确认家映可访问本地网络")
                        Text("3. 确认 NAS、家庭媒体服务和 Jellyfin 已启动")
                        Text("4. 回到设置检查 IP 地址与端口")
                        Text("5. 仍然失败时，拍下上面的诊断信息")
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(80)
            }
        }
        .navigationTitle("诊断")
        .onAppear(perform: refreshDiagnosticEvents)
        .onDisappear(perform: taskController.cancel)
    }

    private func statusRow(
        _ title: String,
        status: ClientDiagnosticConnectionStatus,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(status))
                .foregroundStyle(statusTint(status))
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.displayText)
                    .fontWeight(.semibold)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 760)
    }

    private var report: ClientDiagnosticsReport {
        ClientDiagnosticsReport(
            buildInfo: buildInfo,
            deviceDescription: "Apple TV · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            familyMediaAddress: familyStore.serverURLText,
            familyMediaStatus: familyStatus,
            jellyfinAddress: jellyfinStore.serverURLText,
            jellyfinStatus: jellyfinStatus,
            isJellyfinLoggedIn: jellyfinStore.session != nil,
            recentEvents: diagnosticEvents
        )
    }

    private var familyStatus: ClientDiagnosticConnectionStatus {
        familyStore.connectionStatus
    }

    private var jellyfinStatus: ClientDiagnosticConnectionStatus {
        jellyfinStore.connectionStatus
    }

    private func statusIcon(_ status: ClientDiagnosticConnectionStatus) -> String {
        switch status {
        case .unchecked: "questionmark.circle"
        case .available: "checkmark.circle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    private func statusTint(_ status: ClientDiagnosticConnectionStatus) -> Color {
        switch status {
        case .unchecked: .secondary
        case .available: .green
        case .unavailable: .orange
        }
    }

    @MainActor
    private func checkConnections() async {
        guard !isChecking else { return }
        isChecking = true
        async let familyCheck: Void = familyStore.checkConnection()
        async let jellyfinCheck: Void = jellyfinStore.checkConnection()
        _ = await (familyCheck, jellyfinCheck)
        jellyfinStore.refreshSession()
        refreshDiagnosticEvents()
        isChecking = false
    }

    private func refreshDiagnosticEvents() {
        diagnosticEvents = ClientEventLog.shared.recentEvents(limit: 30)
    }
}
