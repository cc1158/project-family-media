import Foundation

public struct HealthStatusPresentation: Equatable, Sendable {
    public let title: String
    public let rows: [SettingsStatusRow]

    public init(status: HealthStatus) {
        title = status.status == "ok" ? "家庭媒体可用" : "可以连接，但部分功能可能不可用"

        var rows = Self.orderedChecks.compactMap { key, title -> SettingsStatusRow? in
            guard let check = status.checks[key] else { return nil }
            return SettingsStatusRow(
                title: title,
                value: Self.message(for: key, check: check),
                isHealthy: check.status == "ok"
            )
        }

        var serviceRows: [SettingsStatusRow] = []
        if let build = status.build {
            serviceRows.append(
                SettingsStatusRow(
                    title: "服务版本",
                    value: "\(build.version) · \(build.commit)",
                    isHealthy: true
                )
            )
            serviceRows.append(
                SettingsStatusRow(
                    title: "运行程序",
                    value: Self.binarySourceMessage(build.source),
                    isHealthy: Self.knownBinarySources.contains(build.source)
                )
            )
        }

        if let apiVersion = status.apiVersion {
            serviceRows.append(
                SettingsStatusRow(
                    title: "服务接口",
                    value: "版本 \(apiVersion) · 已兼容",
                    isHealthy: true
                )
            )
        }
        rows.insert(contentsOf: serviceRows, at: 0)

        if let scan = status.scan {
            rows.append(
                SettingsStatusRow(
                    title: "最近扫描",
                    value: Self.scanMessage(scan),
                    isHealthy: scan.status != "failed" && scan.thumbnailError.isEmpty
                )
            )
        }

        self.rows = rows
    }

    private static let orderedChecks: [(String, String)] = [
        ("mediaRoot", "媒体文件"),
        ("thumbnailCache", "封面缓存"),
        ("indexDatabase", "内容索引"),
        ("ffmpeg", "视频处理")
    ]

    private static let knownBinarySources: Set<String> = ["external", "bundled", "development"]

    private static func binarySourceMessage(_ source: String) -> String {
        switch source {
        case "external": "NAS 外置程序"
        case "bundled": "镜像内置程序"
        case "development": "开发环境"
        default: "来源未知"
        }
    }

    private static func message(for key: String, check: HealthCheck) -> String {
        switch (key, check.status, check.message) {
        case ("mediaRoot", "ok", _):
            return "可读取"
        case ("mediaRoot", _, _):
            return "无法读取，请检查媒体目录权限"
        case ("thumbnailCache", "ok", _), ("indexDatabase", "ok", _):
            return "可写入"
        case ("thumbnailCache", _, _):
            return "无法写入，请检查缓存目录权限"
        case ("indexDatabase", _, _):
            return "无法使用，请检查数据目录权限"
        case ("ffmpeg", "ok", _):
            return "可用"
        case ("ffmpeg", _, _):
            return "不可用，部分视频可能没有封面"
        default:
            return "需要检查"
        }
    }

    private static func scanMessage(_ scan: HealthScanSummary) -> String {
        var message: String
        switch scan.status {
        case "idle": message = "尚未更新"
        case "running": message = "正在更新"
        case "completed": message = "更新完成"
        case "failed": message = "更新失败"
        default: message = "状态未知"
        }
        if !scan.thumbnailError.isEmpty {
            message += "，但部分封面未能生成"
        } else if !scan.error.isEmpty {
            message += "，请稍后重试"
        }
        return message
    }
}
