import Foundation

enum BackendConfiguration {
    static var baseURL: URL? {
        let keys = ["HollowAPIURL", "HollowFoodAPIURL"]
        let value = keys.compactMap { key in
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.first { !$0.isEmpty }

        guard let value,
              let components = URLComponents(string: value),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }

        let localHost = host == "localhost" || host.hasSuffix(".local")
        guard components.scheme == "https" || (components.scheme == "http" && localHost) else {
            return nil
        }
        return components.url
    }
}
