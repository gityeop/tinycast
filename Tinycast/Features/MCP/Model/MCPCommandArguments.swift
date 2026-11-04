import Foundation

enum MCPCommandArguments {
    static func text(_ arguments: [String]) -> String {
        arguments.map { argument in
            guard argument.isEmpty || argument.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" }) else {
                return argument
            }
            return "'" + argument.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }.joined(separator: " ")
    }

    static func parse(_ text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var started = false
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started { arguments.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { arguments.append(current) }
        return arguments
    }
}
