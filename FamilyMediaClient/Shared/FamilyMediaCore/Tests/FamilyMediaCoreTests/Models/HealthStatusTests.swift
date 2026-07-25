import Foundation
import Testing
@testable import FamilyMediaCore

struct HealthStatusTests {
    @Test func decodesLegacyHealthStatus() throws {
        let data = Data(#"{"status":"ok"}"#.utf8)

        let status = try JSONDecoder.familyMedia.decode(HealthStatus.self, from: data)

        #expect(status.status == "ok")
        #expect(status.apiVersion == nil)
        #expect(status.capabilities.isEmpty)
        #expect(status.build == nil)
        #expect(status.checks.isEmpty)
        #expect(status.scan == nil)
    }

    @Test func decodesDiagnosticHealthStatus() throws {
        let data = Data(
            """
            {
              "status": "degraded",
              "apiVersion": 2,
              "capabilities": ["folder_browse", "generated_data_clear"],
              "build": {
                "version": "local",
                "commit": "64f1307-dirty",
                "builtAt": "2026-07-19T06:30:00Z",
                "source": "external"
              },
              "checks": {
                "mediaRoot": { "status": "ok", "message": "readable" },
                "ffmpeg": { "status": "warning", "message": "not available" }
              },
              "scan": {
                "status": "completed",
                "jobId": "scan-1",
                "finishedAt": "2026-07-05T12:00:00Z",
                "thumbnailError": "kids/broken.mp4: ffmpeg not found"
              }
            }
            """.utf8
        )

        let status = try JSONDecoder.familyMedia.decode(HealthStatus.self, from: data)

        #expect(status.status == "degraded")
        #expect(status.apiVersion == 2)
        #expect(status.capabilities.contains("folder_browse"))
        #expect(status.build?.version == "local")
        #expect(status.build?.commit == "64f1307-dirty")
        #expect(status.build?.source == "external")
        #expect(status.checks["mediaRoot"]?.status == "ok")
        #expect(status.checks["ffmpeg"]?.message == "not available")
        #expect(status.scan?.jobId == "scan-1")
        #expect(status.scan?.thumbnailError == "kids/broken.mp4: ffmpeg not found")
    }

    @Test func incompleteBuildIdentityDoesNotBreakHealthCheck() throws {
        let data = Data(#"{"status":"ok","build":{"source":"bundled"}}"#.utf8)

        let status = try JSONDecoder.familyMedia.decode(HealthStatus.self, from: data)

        #expect(status.build?.source == "bundled")
        #expect(status.build?.version == "unknown")
        #expect(status.build?.commit == "unknown")
        #expect(status.build?.builtAt == "unknown")
    }
}
