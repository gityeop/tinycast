import Foundation

enum MCPDocumentationService {
    struct Page: Sendable {
        let text: String
        let repository: URL?
    }

    static func fetch(_ source: URL) async throws -> MCPDocumentation {
        try await fetch(source, load: download)
    }

    static func fetch(
        _ source: URL, load: @Sendable (URL) async throws -> Page
    ) async throws -> MCPDocumentation {
        let page = try await load(source)
        guard source.host() != "github.com", let repository = page.repository else {
            return MCPDocumentation(text: page.text, sources: [source])
        }
        try Task.checkCancellation()
        let readme = try await load(repository)
        return MCPDocumentation(
            text: "Source listing: \(source.absoluteString)\n\(page.text)\n\n"
                + "Repository README: \(repository.absoluteString)\n\(readme.text)",
            sources: [source, repository])
    }

    static func page(body: String, isHTML: Bool, source: URL) throws -> Page {
        let repository = isHTML && source.host() != "github.com"
            ? try MCPSetupLink.declaredRepository(in: body) : nil
        let entries = isHTML ? try MCPSetupLink.repositoryEntries(in: body, source: source) : []
        var body = body
        if source.host() == "github.com", isHTML {
            if let article = body.range(
                of: #"(?is)<article\b[^>]*class="[^"]*markdown-body[^"]*"[^>]*>.*?</article>"#,
                options: .regularExpression) {
                body = String(body[article])
            } else if source.pathComponents.contains("tree"), !entries.isEmpty {
                body = "Repository directory: " + source.absoluteString
            } else {
                throw AIProviderError.responseFailed("This GitHub page has no readable README. Use a specific setup guide link.")
            }
        }
        var text = MCPSetupLink.readableText(body, isHTML: isHTML)
        if !entries.isEmpty {
            text += "\n\nRepository files and directories:\n" + entries.prefix(100).map(\.absoluteString).joined(separator: "\n")
        }
        guard !text.isEmpty else {
            throw AIProviderError.responseFailed("The link returned no readable documentation.")
        }
        return Page(text: text, repository: repository)
    }

    private static func download(_ source: URL) async throws -> Page {
        let url = try MCPSetupLink.documentationURL(for: source)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("text/markdown, text/html, text/plain", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIProviderError.malformedResponse }
        guard (200...299).contains(response.statusCode) else {
            throw AIProviderError.responseFailed(
                "The documentation site returned HTTP \(response.statusCode). Check the public link.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8_388_608 else {
                throw AIProviderError.responseFailed("This documentation page is too large. Use a direct setup guide link.")
            }
            data.append(byte)
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw AIProviderError.responseFailed("The documentation page is not readable UTF-8 text.")
        }
        return try page(body: body, isHTML: response.mimeType == "text/html", source: url)
    }
}
