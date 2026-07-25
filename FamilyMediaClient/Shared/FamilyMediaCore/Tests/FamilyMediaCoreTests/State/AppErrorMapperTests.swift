import Foundation
import Testing
@testable import FamilyMediaCore

struct AppErrorMapperTests {
    @Test func mapsConnectionFailure() {
        let message = AppErrorMapper.message(for: URLError(.cannotConnectToHost))

        #expect(message.contains("无法连接"))
        #expect(message.contains("同一家庭网络"))
        #expect(message.contains("NAS 已开机"))
        #expect(message.contains("本地网络权限"))
    }

    @Test func mapsSystemNetworkRestriction() {
        let message = AppErrorMapper.message(for: URLError(.dataNotAllowed))

        #expect(message.contains("系统设置"))
        #expect(message.contains("本地网络权限"))
    }

    @Test func mapsTimeout() {
        let message = AppErrorMapper.message(for: URLError(.timedOut))

        #expect(message.contains("连接等待时间过长"))
        #expect(message.contains("NAS"))
    }

    @Test func mapsInvalidHTTPSCertificate() {
        let message = AppErrorMapper.message(for: URLError(.serverCertificateUntrusted))

        #expect(message.contains("安全连接"))
        #expect(message.contains("证书"))
    }

    @Test func mapsKnownServerErrorCode() {
        let message = AppErrorMapper.message(
            for: APIClientError.unacceptableStatusCode(500, "regenerate_thumbnail_failed")
        )

        #expect(message.contains("封面生成失败"))
        #expect(message.contains("家庭媒体服务"))
    }

    @Test func hidesUnknownHTTPAndDecodingImplementationDetails() {
        let serverMessage = AppErrorMapper.message(
            for: APIClientError.unacceptableStatusCode(503, "internal_database_failure")
        )
        let decodingMessage = AppErrorMapper.message(
            for: APIClientError.decodingFailed(
                "keyNotFound(CodingKeys(stringValue: privatePath))"
            )
        )

        #expect(serverMessage.contains("暂时出错"))
        #expect(!serverMessage.contains("503"))
        #expect(!serverMessage.contains("internal_database_failure"))
        #expect(decodingMessage.contains("无法识别"))
        #expect(!decodingMessage.contains("privatePath"))
    }

    @Test func hidesJellyfinStatusCodeFromHouseholdFacingMessage() {
        let message = AppErrorMapper.message(for: JellyfinError.server(502))

        #expect(message == "Jellyfin 服务暂时出错，请稍后重新尝试。")
        #expect(!message.contains("502"))
    }
}
