import Foundation

struct JellyfinPlaybackURLBuilder: Sendable {
    let baseURL: URL

    func authenticatedURL(from path: String, token: String) -> URL? {
        guard let incoming = URLComponents(string: path) else { return nil }
        var components: URLComponents

        if incoming.scheme != nil || incoming.host != nil {
            guard let absoluteURL = incoming.url,
                  isSameOrigin(absoluteURL),
                  let absoluteComponents = URLComponents(
                    url: absoluteURL,
                    resolvingAgainstBaseURL: false
                  )
            else { return nil }
            components = absoluteComponents
        } else {
            guard var relativeComponents = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
            ) else { return nil }

            let basePath = normalizedBasePath(relativeComponents.percentEncodedPath)
            let incomingPath = incoming.percentEncodedPath
            if !basePath.isEmpty,
               (incomingPath == basePath || incomingPath.hasPrefix(basePath + "/")) {
                relativeComponents.percentEncodedPath = incomingPath
            } else {
                let normalizedIncoming = incomingPath.hasPrefix("/")
                    ? String(incomingPath.dropFirst())
                    : incomingPath
                relativeComponents.percentEncodedPath = basePath + "/" + normalizedIncoming
            }
            relativeComponents.percentEncodedQuery = incoming.percentEncodedQuery
            components = relativeComponents
        }

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "api_key" }) {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func normalizedBasePath(_ path: String) -> String {
        guard path != "/" else { return "" }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func isSameOrigin(_ candidate: URL) -> Bool {
        candidate.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && candidate.host?.lowercased() == baseURL.host?.lowercased()
            && effectivePort(candidate) == effectivePort(baseURL)
    }

    private func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
