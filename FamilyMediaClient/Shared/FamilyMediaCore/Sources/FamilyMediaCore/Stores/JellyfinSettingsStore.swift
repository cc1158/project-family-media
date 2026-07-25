import Combine
import Foundation

@MainActor
public final class JellyfinSettingsStore: ObservableObject {
    @Published public var serverURLText: String
    @Published public var username = ""
    @Published public var password = ""
    @Published public private(set) var session: JellyfinSession?
    @Published public private(set) var serverInfo: JellyfinServerInfo?
    @Published public private(set) var message: AppMessage?
    @Published public private(set) var isWorking = false
    @Published public private(set) var connectionStatus: ClientDiagnosticConnectionStatus = .unchecked

    private let service: JellyfinService
    private let configuration: JellyfinConfigurationStore
    private let sourceRefreshCenter: MediaSourceRefreshCenter
    private var sourceRefreshCancellable: AnyCancellable?

    public init(
        service: JellyfinService,
        configuration: JellyfinConfigurationStore,
        sourceRefreshCenter: MediaSourceRefreshCenter = MediaSourceRefreshCenter()
    ) {
        self.service = service
        self.configuration = configuration
        self.sourceRefreshCenter = sourceRefreshCenter
        serverURLText = configuration.serverBaseURL.absoluteString
        session = service.currentSession
        username = session?.username ?? ""
        sourceRefreshCancellable = sourceRefreshCenter.$generation
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshSession(publishRefresh: false)
            }
    }

    @discardableResult
    public func saveAddress() -> Bool {
        saveAddress(publishRefresh: true)
    }

    private func saveAddress(publishRefresh: Bool) -> Bool {
        guard let url = ServerAddressNormalizer.normalize(serverURLText) else {
            connectionStatus = .unavailable
            message = .warning("Jellyfin 地址格式不正确")
            return false
        }

        let previousURL = ServerAddressNormalizer.normalize(configuration.serverBaseURL.absoluteString)
        let didChangeAddress = previousURL != url
        if didChangeAddress {
            service.logout()
            session = nil
            serverInfo = nil
            connectionStatus = .unchecked
        }
        configuration.serverBaseURL = url
        serverURLText = url.absoluteString
        message = .success("Jellyfin 地址已保存")
        if didChangeAddress, publishRefresh {
            sourceRefreshCenter.publishRefresh(for: .jellyfin)
        }
        return true
    }

    public func checkConnection() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        guard saveAddress(publishRefresh: false) else { return }
        defer {
            refreshSession(publishRefresh: false)
            sourceRefreshCenter.publishRefresh(for: .jellyfin)
        }
        do {
            serverInfo = try await service.inspectConnection()
            connectionStatus = .available
            message = .success("Jellyfin 服务正常")
        } catch let error where TaskCancellation.matches(error) {
            return
        } catch JellyfinError.unauthorized {
            // A 401 proves the server is reachable even though the saved login expired.
            connectionStatus = .available
            message = .failure(JellyfinError.unauthorized.localizedDescription)
        } catch {
            connectionStatus = .unavailable
            message = .failure(AppErrorMapper.message(for: error))
        }
    }

    public func login() async {
        guard !isWorking else { return }
        isWorking = true
        defer {
            password = ""
            isWorking = false
        }

        guard saveAddress(publishRefresh: false) else { return }
        defer { sourceRefreshCenter.publishRefresh(for: .jellyfin) }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = .warning("请输入 Jellyfin 用户名")
            return
        }

        do {
            session = try await service.login(username: username, password: password)
            serverInfo = try? await service.publicInfo()
            connectionStatus = .available
            message = .success("Jellyfin 登录成功")
        } catch let error where TaskCancellation.matches(error) {
            return
        } catch JellyfinError.invalidCredentials {
            // Authentication failed, but the Jellyfin server answered normally.
            connectionStatus = .available
            message = .failure(JellyfinError.invalidCredentials.localizedDescription)
        } catch {
            connectionStatus = .unavailable
            message = .failure(AppErrorMapper.message(for: error))
        }
    }

    public func logout() {
        service.logout()
        session = nil
        password = ""
        message = .success("已退出 Jellyfin")
        sourceRefreshCenter.publishRefresh(for: .jellyfin)
    }

    public func clearSensitiveInput() {
        password = ""
    }

    public func refreshSession(publishRefresh: Bool = true) {
        let previousSession = session
        let currentSession = service.currentSession
        if session != nil, currentSession == nil {
            serverInfo = nil
            password = ""
            message = .warning("Jellyfin 登录已失效，请重新登录")
        }
        session = currentSession
        if let currentSession {
            username = currentSession.username
        }
        if previousSession != currentSession, publishRefresh {
            sourceRefreshCenter.publishRefresh(for: .jellyfin)
        }
    }
}
