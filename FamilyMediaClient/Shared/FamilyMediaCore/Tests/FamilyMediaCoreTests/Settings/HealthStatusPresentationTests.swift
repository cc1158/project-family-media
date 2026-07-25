import Testing
@testable import FamilyMediaCore

struct HealthStatusPresentationTests {
    @Test func showsCompatibleServerAPIVersion() {
        let status = HealthStatus(
            status: "ok",
            apiVersion: 2,
            capabilities: ["folder_browse", "generated_data_clear"]
        )

        let presentation = HealthStatusPresentation(status: status)

        #expect(presentation.rows.first?.title == "服务接口")
        #expect(presentation.rows.first?.value == "版本 2 · 已兼容")
        #expect(presentation.rows.first?.isHealthy == true)
    }

    @Test func showsBuildVersionCommitAndExternalBinarySource() {
        let status = HealthStatus(
            status: "ok",
            apiVersion: 2,
            build: ServerBuildInfo(
                version: "local",
                commit: "64f1307-dirty",
                builtAt: "2026-07-19T06:30:00Z",
                source: "external"
            )
        )

        let rows = HealthStatusPresentation(status: status).rows

        #expect(rows.first { $0.title == "服务版本" }?.value == "local · 64f1307-dirty")
        #expect(rows.first { $0.title == "运行程序" }?.value == "NAS 外置程序")
        #expect(rows.first { $0.title == "运行程序" }?.isHealthy == true)
    }

    @Test func developmentBinarySourceIsClearlyIdentified() {
        let status = HealthStatus(
            status: "ok",
            build: ServerBuildInfo(
                version: "development",
                commit: "unknown",
                builtAt: "unknown",
                source: "development"
            )
        )

        let row = HealthStatusPresentation(status: status).rows.first { $0.title == "运行程序" }

        #expect(row?.value == "开发环境")
        #expect(row?.isHealthy == true)
    }

    @Test func unknownBinarySourceShowsAWarning() {
        let status = HealthStatus(
            status: "ok",
            build: ServerBuildInfo(
                version: "future",
                commit: "abc1234",
                builtAt: "2026-07-20T00:00:00Z",
                source: "future-source"
            )
        )

        let row = HealthStatusPresentation(status: status).rows.first { $0.title == "运行程序" }

        #expect(row?.value == "来源未知")
        #expect(row?.isHealthy == false)
    }

    @Test func surfacesThumbnailErrorInLatestScanRow() {
        let status = HealthStatus(
            status: "degraded",
            scan: HealthScanSummary(
                status: "completed",
                jobId: "scan-1",
                thumbnailError: "kids/broken.mp4: ffmpeg not found"
            )
        )

        let presentation = HealthStatusPresentation(status: status)
        let row = presentation.rows.first { $0.title == "最近扫描" }

        #expect(presentation.title == "可以连接，但部分功能可能不可用")
        #expect(row?.value == "更新完成，但部分封面未能生成")
        #expect(row?.isHealthy == false)
    }

    @Test func hidesUnknownServerStateAndJobIdentifier() {
        let status = HealthStatus(
            status: "degraded",
            scan: HealthScanSummary(status: "future-state", jobId: "private-job-id")
        )

        let presentation = HealthStatusPresentation(status: status)
        let row = presentation.rows.first { $0.title == "最近扫描" }

        #expect(row?.value == "状态未知")
        #expect(row?.value.contains("private-job-id") == false)
    }

    @Test func replacesRawFilesystemErrorsWithHouseholdGuidance() {
        let status = HealthStatus(
            status: "degraded",
            checks: [
                "mediaRoot": HealthCheck(
                    status: "error",
                    message: "permission denied: /volume1/private/family"
                ),
                "indexDatabase": HealthCheck(
                    status: "error",
                    message: "sqlite open /data/private/index.db failed"
                )
            ]
        )

        let presentation = HealthStatusPresentation(status: status)
        let values = presentation.rows.map(\.value)

        #expect(values.contains("无法读取，请检查媒体目录权限"))
        #expect(values.contains("无法使用，请检查数据目录权限"))
        #expect(values.allSatisfy { !$0.contains("/volume1") && !$0.contains("/data") })
    }
}
