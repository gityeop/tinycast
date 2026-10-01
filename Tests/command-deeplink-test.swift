import Foundation

@main
@MainActor
struct CommandDeepLinkTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() {
        leaderKeyLinks()
        copiedLinks()
        invalidNativeLinks()
        extensionLinks()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func leaderKeyLinks() {
        let configured: [(String, CommandID)] = [
            ("oncast://command/search-emoji", .searchEmoji),
            ("oncast://command/open-camera", .openCamera),
            ("oncast://command/confetti", .confetti),
            ("tinycast://command/search-emoji", .searchEmoji),
            ("tinycast://command/open-camera", .openCamera),
            ("tinycast://extensions/raycast/raycast/confetti", .confetti),
            ("tinycast://command/confetti", .confetti)
        ]
        for (address, command) in configured {
            let url = URL(string: address)!
            check("configured link is a native command: \(address)", CommandDeepLink.claims(url))
            check("configured link reaches \(command.name)", CommandDeepLink.parse(url) == command)
        }

        let legacy: [(String, CommandID)] = [
            ("raycast://extensions/raycast/emoji-symbols/search-emoji-symbols", .searchEmoji),
            ("raycast-x://extensions/raycast/raycast/open-camera", .openCamera),
            ("raycast://extensions/raycast/raycast/open-camera", .openCamera),
            ("raycast://extensions/raycast/raycast/confetti", .confetti)
        ]
        for (address, command) in legacy {
            check(
                "existing Raycast link reaches \(command.name)",
                CommandDeepLink.parse(URL(string: address)!) == command)
        }
    }

    static func copiedLinks() {
        var addresses = Set<URL>()
        for command in CommandID.allCases where !command.isQueryDriven {
            guard let url = CommandDeepLink.url(for: command) else {
                check("\(command.name) can be copied", false)
                continue
            }
            check("copied \(command.name) opens Oncast", url.scheme == "oncast")
            check(
                "copied \(command.name) dispatches its original command",
                CommandDeepLink.parse(url) == command)
            check("copied commands have distinct links", addresses.insert(url).inserted)
        }
        check(
            "emoji uses the documented address",
            CommandDeepLink.url(for: .searchEmoji)?.absoluteString == "oncast://command/search-emoji")
        check(
            "camera uses the documented address",
            CommandDeepLink.url(for: .openCamera)?.absoluteString == "oncast://command/open-camera")
        check(
            "confetti copies its native address",
            CommandDeepLink.url(for: .confetti)?.absoluteString == "oncast://command/confetti")
        check("browser query has no input-free link", CommandDeepLink.url(for: .openInBrowser) == nil)
        check("shell query has no input-free link", CommandDeepLink.url(for: .runShellCommand) == nil)
    }

    static func invalidNativeLinks() {
        let invalid = [
            "oncast://command/unknown",
            "tinycast://command/unknown",
            "tinycast://command",
            "tinycast://command/open-camera/extra",
            "tinycast://command/open-in-browser",
            "tinycast://command/run-shell-command",
            "tinycast://command/search-emoji?query=smile",
            "tinycast://command/open-camera#camera",
            "raycast://extensions/raycast/raycast/confetti?arguments=%7B%7D"
        ]
        for address in invalid {
            let url = URL(string: address)!
            check(
                "invalid native route stays in native error handling: \(address)",
                CommandDeepLink.claims(url))
            check("invalid native route cannot run: \(address)", CommandDeepLink.parse(url) == nil)
        }
        for address in ["https://command/open-camera", "other://command/search-emoji"] {
            let url = URL(string: address)!
            check("another app's scheme is not claimed", !CommandDeepLink.claims(url))
            check("another app's scheme cannot run a command", CommandDeepLink.parse(url) == nil)
        }
    }

    static func extensionLinks() {
        let addresses = [
            "oncast://extensions/thomas/color-picker/pick-color",
            "oncast://extensions/color-picker/pick-color",
            "tinycast://extensions/thomas/color-picker/pick-color",
            "raycast://extensions/thomas/color-picker/pick-color",
            "tinycast://extensions/color-picker/pick-color"
        ]
        for address in addresses {
            let url = URL(string: address)!
            check("Color Picker stays with extension routing", !CommandDeepLink.claims(url))
            check("Color Picker is not a built-in command", CommandDeepLink.parse(url) == nil)
            let link = ExtensionDeepLink.parse(url: url)
            check("Color Picker retains its installed extension", link?.extensionName == "color-picker")
            check("Color Picker retains its command", link?.commandName == "pick-color")
        }
        for extensionName in ["thomas/color-picker", "color-picker"] {
            guard let url = ExtensionDeepLink.url(
                extensionName: extensionName, commandName: "pick-color")
            else {
                check("installed extension command has a copyable address", false)
                continue
            }
            check("copied extension command opens Oncast", url.scheme == "oncast")
            let link = ExtensionDeepLink.parse(url: url)
            check(
                "copied extension link resolves the same install",
                link?.matches(manifestName: extensionName) == true)
            check("copied extension link retains its command", link?.commandName == "pick-color")
        }
        for scheme in ["oncast", "tinycast"] {
            check(
                "OAuth callbacks stay with OAuth routing",
                !CommandDeepLink.claims(URL(string: "\(scheme)://oauth?code=abc")!))
        }
    }
}
