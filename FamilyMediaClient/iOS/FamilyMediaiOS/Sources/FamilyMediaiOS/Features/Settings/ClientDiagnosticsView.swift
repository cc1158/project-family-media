import FamilyMediaCore
import SwiftUI
import UIKit

struct ClientDiagnosticsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @ObservedObject var familyStore: SettingsStore
    @ObservedObject var jellyfinStore: JellyfinSettingsStore
    let buildInfo: ClientBuildInfo

    @State private var isChecking = false
    @State private var didCopy = false
    @State private var diagnosticEvents: [ClientDiagnosticEvent] = []
    @StateObject private var taskController = ViewTaskController()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SettingsCard(
                        title: "连接状态",
                        subtitle: "同时检查两个内容来源",
                        systemImage: "stethoscope",
                        tint: .orange
                    ) {
                        diagnosticRow(
                            title: "家庭媒体",
                            status: familyStatus
                        )
                        Divider().overlay(.white.opacity(0.08))
                        diagnosticRow(
                            title: "Jellyfin",
                            status: jellyfinStatus,
                            detail: jellyfinStore.session == nil ? "未登录" : "已登录"
                        )

                        SettingsActionButton(
                            title: isChecking ? "正在检查…" : "重新检查连接",
                            systemImage: "arrow.clockwise",
                            prominent: true
                        ) {
                            taskController.run { await checkConnections() }
                        }
                        .disabled(isChecking)
                    }

                    SettingsCard(
                        title: "诊断信息",
                        subtitle: "可发送给维护人员帮助排查",
                        systemImage: "doc.text.magnifyingglass",
                        tint: FamilyMediaTheme.accent
                    ) {
                        Text(report.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        SettingsActionButton(
                            title: didCopy ? "已复制" : "复制诊断信息",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc",
                            prominent: false
                        ) {
                            UIPasteboard.general.string = report.text
                            didCopy = true
                        }
                    }

                    privacyNotice
                    troubleshooting
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("帮助与诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .familyNavigationStyle()
        .onChange(of: report.text) {
            didCopy = false
        }
        .onAppear(perform: refreshDiagnosticEvents)
        .onDisappear(perform: taskController.cancel)
    }

    private func diagnosticRow(
        title: String,
        status: ClientDiagnosticConnectionStatus,
        detail: String? = nil
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticTitle(title, status: status)
                    diagnosticValue(status, detail: detail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    diagnosticTitle(title, status: status)
                    Spacer()
                    diagnosticValue(status, detail: detail)
                }
            }
        }
    }

    private func diagnosticTitle(
        _ title: String,
        status: ClientDiagnosticConnectionStatus
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon(status))
                .foregroundStyle(statusTint(status))
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }

    private func diagnosticValue(
        _ status: ClientDiagnosticConnectionStatus,
        detail: String?
    ) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(status.displayText)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyNotice: some View {
        Label(
            "诊断信息不会包含密码、登录凭证、媒体名称或设备标识；网址中的附加参数会被自动移除。",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var troubleshooting: some View {
        SettingsCard(
            title: "连接不上时",
            subtitle: "按顺序检查通常可以解决",
            systemImage: "questionmark.circle.fill",
            tint: FamilyMediaTheme.purple
        ) {
            troubleshootingRow("确认 iPhone 与 NAS 在同一个家庭网络")
            troubleshootingRow("确认家映已允许访问本地网络")
            troubleshootingRow("确认 NAS、家庭媒体服务和 Jellyfin 已启动")
            troubleshootingRow("确认地址中的 IP 和端口没有变化")
            troubleshootingRow("仍然失败时，复制上面的诊断信息")

            SettingsActionButton(
                title: "打开家映系统设置",
                systemImage: "gearshape.fill",
                prominent: false
            ) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .accessibilityIdentifier("diagnostics.open-system-settings")
            .accessibilityHint("可以在系统设置中检查本地网络权限")
        }
    }

    private func troubleshootingRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var report: ClientDiagnosticsReport {
        ClientDiagnosticsReport(
            buildInfo: buildInfo,
            deviceDescription: "\(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
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
        didCopy = false
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
