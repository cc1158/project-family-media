import Foundation

public struct ScanStatusPresentation: Equatable, Sendable {
    public static let failureGuidance = "家庭媒体更新未能完成，请检查 NAS 存储空间和媒体目录权限后重试。"

    public let status: String
    public let rows: [SettingsStatusRow]
    public let error: String?

    public init(scanStatus: ScanStatus) {
        status = scanStatus.status.displayText
        var availableRows = [SettingsStatusRow]()
        availableRows.appendIfPresent(title: "已检查文件", value: scanStatus.scannedFiles)
        availableRows.appendIfPresent(title: "新增或更新", value: scanStatus.indexedFiles)
        availableRows.appendIfPresent(title: "已移除", value: scanStatus.deletedFiles)
        availableRows.appendIfPresent(title: "信息读取成功", value: scanStatus.metadataExtracted)
        availableRows.appendIfPresent(title: "信息不完整", value: scanStatus.metadataMissing)
        availableRows.appendIfPresent(title: "信息读取失败", value: scanStatus.metadataFailed, isHealthy: false)
        availableRows.appendIfPresent(title: "使用基础信息", value: scanStatus.metadataFallback)
        availableRows.appendIfPresent(title: "封面待生成", value: scanStatus.thumbnailPending)
        availableRows.appendIfPresent(title: "封面生成成功", value: scanStatus.thumbnailGenerated)
        availableRows.appendIfPresent(title: "封面生成失败", value: scanStatus.thumbnailFailed, isHealthy: false)
        if !scanStatus.thumbnailError.isEmpty {
            availableRows.append(
                SettingsStatusRow(
                    title: "封面状态",
                    value: "部分封面未能生成",
                    isHealthy: false
                )
            )
        }
        rows = availableRows
        error = scanStatus.status == .failed || !scanStatus.error.isEmpty
            ? Self.failureGuidance
            : nil
    }
}

private extension ScanState {
    var displayText: String {
        switch self {
        case .idle: "尚未更新"
        case .running: "正在更新"
        case .completed: "更新完成"
        case .failed: "更新失败"
        }
    }
}

private extension Array where Element == SettingsStatusRow {
    mutating func appendIfPresent(
        title: String,
        value: Int?,
        isHealthy: Bool = true
    ) {
        guard let value else { return }
        append(SettingsStatusRow(title: title, value: String(value), isHealthy: isHealthy))
    }
}
