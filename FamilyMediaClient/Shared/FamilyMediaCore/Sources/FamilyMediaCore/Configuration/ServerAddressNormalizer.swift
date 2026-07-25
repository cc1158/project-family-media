import Foundation

enum ServerAddressNormalizer {
    static func normalize(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return nil }

        components.scheme = scheme
        components.host = components.host?.lowercased()
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }

        let path = components.percentEncodedPath
        if path == "/" {
            components.percentEncodedPath = ""
        } else if path.hasSuffix("/") {
            components.percentEncodedPath = String(path.dropLast())
        }
        return components.url
    }
}
