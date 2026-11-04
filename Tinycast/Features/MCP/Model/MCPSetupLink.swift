import Foundation

enum MCPSetupLink {
    static func documentationURL(for source: URL) throws -> URL {
        guard source.scheme == "https", source.user == nil, source.password == nil else {
            throw AIProviderError.responseFailed("Use a public HTTPS documentation link without credentials.")
        }
        guard source.host()?.lowercased() == "github.com" else { return source }
        let parts = source.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else {
            throw AIProviderError.responseFailed("Use a GitHub repository or README file link.")
        }
        if parts.count == 2 {
            return source
        }
        if parts.count >= 4, parts[2] == "tree" { return source }
        guard parts.count >= 5, parts[2] == "blob" else {
            throw AIProviderError.responseFailed("Use the repository's main link or a specific README file link.")
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "raw.githubusercontent.com"
        components.path = "/" + ([parts[0], parts[1]] + parts.dropFirst(3)).joined(separator: "/")
        guard let url = components.url else { throw AIProviderError.malformedResponse }
        return url
    }

    static func readableText(_ body: String, isHTML: Bool) -> String {
        guard isHTML else { return body }
        var text = body.replacingOccurrences(
            of: #"(?is)<(script|style|nav|svg)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?is)<a\b[^>]*href=["'](https://[^"']+)["'][^>]*>(.*?)</a>"#,
            with: "[$2]($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression)
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func declaredRepository(in html: String) throws -> URL? {
        let expression = try NSRegularExpression(
            pattern: #"(?is)<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#)
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var repositories = Set<URL>()
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html),
                let object = try JSONSerialization.jsonObject(with: Data(html[range].utf8)) as? [String: Any],
                let type = object["@type"] as? String,
                type == "SoftwareApplication" || type == "SoftwareSourceCode",
                let address = (object["codeRepository"] ?? object["url"]) as? String,
                let url = URL(string: address), url.scheme == "https", url.host() == "github.com",
                url.pathComponents.filter({ $0 != "/" }).count == 2
            else { continue }
            _ = try documentationURL(for: url)
            repositories.insert(url)
        }
        guard repositories.count <= 1 else {
            throw AIProviderError.responseFailed(
                "This page identifies multiple repositories. Provide the server's exact repository link.")
        }
        return repositories.first
    }

    static func repositoryEntries(in html: String, source: URL) throws -> [URL] {
        guard source.host() == "github.com" else { return [] }
        let parts = source.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return [] }
        let prefix = "/" + parts.prefix(2).joined(separator: "/")
        let expression = try NSRegularExpression(pattern: #"(?is)<a\b[^>]*href=["']([^"']+)["']"#)
        var entries: [URL] = []
        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                let url = URL(string: String(html[range]), relativeTo: source)?.absoluteURL,
                url.host() == "github.com", url.scheme == "https", url != source,
                url.path.hasPrefix(prefix + "/blob/") || url.path.hasPrefix(prefix + "/tree/") else { continue }
            if !entries.contains(url) { entries.append(url) }
        }
        return entries
    }
}
