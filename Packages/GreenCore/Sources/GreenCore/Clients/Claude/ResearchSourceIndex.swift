import Foundation

/// The pages Claude actually retrieved during a research call, read from the `web_search_tool_result`
/// and `web_fetch_tool_result` blocks in the transcript. Search results only expose URLs (their content
/// is encrypted); fetch results also carry the page text, which lets quotes be verified verbatim.
struct ResearchSourceIndex: Sendable {
    private(set) var urls: Set<String> = []
    private(set) var textByURL: [String: String] = [:]

    init(transcript: [JSONValue]) {
        for block in transcript where block["type"]?.string?.hasSuffix("_tool_result") == true {
            collect(block["content"] ?? .null, pageURL: nil)
        }
    }

    /// Pages known only by URL (Grok's web search returns no page text, so quotes are not checked).
    init(retrievedURLs: [URL]) {
        urls = Set(retrievedURLs.map(Self.key(for:)))
    }

    /// True when `url` was retrieved and, if its text is known, the quote appears in it.
    func supports(quote: String, from url: URL) -> Bool {
        let key = Self.key(for: url)
        guard urls.contains(key) else { return false }
        guard let text = textByURL[key] else { return true }
        let fragments = Self.normalize(quote)
            .components(separatedBy: "…").flatMap { $0.components(separatedBy: "...") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return !fragments.isEmpty && fragments.allSatisfy(text.contains)
    }

    private mutating func collect(_ value: JSONValue, pageURL: String?) {
        switch value {
        case .object(let object):
            var page = pageURL
            if let raw = object["url"]?.string, let url = URL(string: raw) {
                let key = Self.key(for: url)
                urls.insert(key)
                page = key
            }
            if let page, let data = object["source"]?["data"]?.string, object["source"]?["type"]?.string == "text" {
                textByURL[page, default: ""] += " " + Self.normalize(data)
            }
            for (key, child) in object where key != "source" { collect(child, pageURL: page) }
        case .array(let items):
            for item in items { collect(item, pageURL: pageURL) }
        default:
            break
        }
    }

    /// Host without "www.", path without trailing slash, query kept, fragment and scheme dropped.
    static func key(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        var host = (components?.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = components?.path ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        let query = components?.query.map { "?\($0)" } ?? ""
        return host + path + query
    }

    /// Lowercased with runs of whitespace collapsed and typographic quotes/dashes unified.
    static func normalize(_ text: String) -> String {
        let unified = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"").replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return unified.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
