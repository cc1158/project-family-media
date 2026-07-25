import Testing
@testable import FamilyMediaCore

struct ScanStatusPresentationTests {
    @Test func formatsCountersAndEmptyValues() {
        let scanStatus = ScanStatus(
            jobId: "scan-1",
            status: .completed,
            scannedFiles: 10,
            indexedFiles: nil,
            deletedFiles: 2,
            metadataExtracted: 7,
            metadataMissing: 1,
            metadataFailed: nil,
            metadataFallback: 2,
            thumbnailPending: 3,
            thumbnailGenerated: 8,
            thumbnailFailed: nil
        )

        let presentation = ScanStatusPresentation(scanStatus: scanStatus)

        #expect(presentation.status == "更新完成")
        #expect(presentation.rows.map(\.title) == [
            "已检查文件",
            "已移除",
            "信息读取成功",
            "信息不完整",
            "使用基础信息",
            "封面待生成",
            "封面生成成功"
        ])
        #expect(presentation.rows.map(\.value) == ["10", "2", "7", "1", "2", "3", "8"])
        #expect(presentation.error == nil)
    }

    @Test func presentsEveryScanStateForHouseholdUsers() {
        #expect(ScanStatusPresentation(scanStatus: ScanStatus(jobId: "idle", status: .idle)).status == "尚未更新")
        #expect(ScanStatusPresentation(scanStatus: ScanStatus(jobId: "running", status: .running)).status == "正在更新")
        #expect(ScanStatusPresentation(scanStatus: ScanStatus(jobId: "completed", status: .completed)).status == "更新完成")
        #expect(ScanStatusPresentation(scanStatus: ScanStatus(jobId: "failed", status: .failed)).status == "更新失败")
    }

    @Test func hidesRawScanFailureBehindActionableGuidance() {
        let scanStatus = ScanStatus(
            jobId: "scan-1",
            status: .failed,
            error: "permission denied: /volume1/private/family"
        )

        let presentation = ScanStatusPresentation(scanStatus: scanStatus)

        #expect(presentation.error == ScanStatusPresentation.failureGuidance)
        #expect(!presentation.error!.contains("/volume1"))
        #expect(presentation.error!.contains("目录权限"))
    }

    @Test func surfacesThumbnailError() {
        let scanStatus = ScanStatus(
            jobId: "scan-1",
            status: .completed,
            thumbnailFailed: 1,
            thumbnailError: "kids/broken.mp4: ffmpeg not found"
        )

        let presentation = ScanStatusPresentation(scanStatus: scanStatus)
        let row = presentation.rows.first { $0.title == "封面状态" }

        #expect(row?.value == "部分封面未能生成")
        #expect(row?.isHealthy == false)
    }
}
