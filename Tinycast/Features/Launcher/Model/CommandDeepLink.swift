import Foundation

/// Native commands share the catalog's stable slugs; extension links keep their own parser.
enum CommandDeepLink {
    private static let schemes = [
        "oncast", "tinycast", "raycast", "raycast-x", "com.raycast", "raycastinternal"
    ]

    private static let raycastCommands: [String: CommandID] = [
        "extensions/raycast/raycast/open-camera": .openCamera,
        "extensions/raycast/raycast/confetti": .confetti,
        "extensions/raycast/emoji-symbols/search-emoji-symbols": .searchEmoji,
    ]

    static func claims(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return false }
        return url.host == "command" || raycastCommands[route(of: url)] != nil
    }

    static func parse(_ url: URL) -> CommandID? {
        guard claims(url), url.query == nil, url.fragment == nil else { return nil }
        if let command = raycastCommands[route(of: url)] { return command }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 1,
            let command = CommandID(rawValue: "command:" + segments[0]), !command.isQueryDriven
        else { return nil }
        return command
    }

    static func url(for command: CommandID) -> URL? {
        guard !command.isQueryDriven else { return nil }
        return URL(string: "oncast://" + command.rawValue.replacingOccurrences(of: ":", with: "/"))
    }

    private static func route(of url: URL) -> String {
        ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }).joined(separator: "/")
    }
}
