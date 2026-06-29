import Foundation

/// Turns user input (a URL, an @handle, or a bare channel ID) into a verified
/// (channelId, displayName) pair. No YouTube Data API key — relies on scraping
/// the public channel page for the canonical `channelId` / `externalId`.
enum ChannelResolver {

    enum ResolveError: LocalizedError {
        case invalidInput
        case notFound
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput: return "Doesn't look like a YouTube channel URL or @handle."
            case .notFound:     return "Couldn't find a channel ID for that URL."
            case .network(let m): return m
            }
        }
    }

    static func resolve(input raw: String) async throws -> (channelId: String, name: String) {
        let pageURL = try pageURL(from: raw)
        var req = URLRequest(url: pageURL)
        // YouTube serves a stripped page without the externalId field to
        // non-browser User-Agents. Send a desktop Safari UA so we get the
        // normal channel page with the embedded data block.
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ResolveError.network("Empty response") }
        guard http.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw ResolveError.network("HTTP \(http.statusCode) loading channel page")
        }

        guard let channelId = extract(pattern: #""(?:externalId|channelId)":"(UC[A-Za-z0-9_-]{22})""#, in: html) else {
            throw ResolveError.notFound
        }

        // Best-effort name: og:title is the cleanest source.
        let name = extract(pattern: #"<meta property="og:title" content="([^"]+)""#, in: html)
            ?? extract(pattern: #""title":"([^"]+)""#, in: html)
            ?? "YouTube channel"

        return (channelId, name)
    }

    private static func pageURL(from raw: String) throws -> URL {
        var s = raw

        // Bare @handle → full URL
        if s.hasPrefix("@") { s = "https://www.youtube.com/\(s)" }
        // Bare UC... id
        if s.hasPrefix("UC") && s.count == 24 {
            return URL(string: "https://www.youtube.com/channel/\(s)")!
        }
        // Missing scheme
        if !s.hasPrefix("http") { s = "https://" + s }

        guard let url = URL(string: s), let host = url.host, host.contains("youtube.com") || host.contains("youtu.be") else {
            throw ResolveError.invalidInput
        }
        return url
    }

    private static func extract(pattern: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let m = re.firstMatch(in: html, range: range), m.numberOfRanges >= 2 else { return nil }
        if let r = Range(m.range(at: 1), in: html) {
            return String(html[r]).replacingOccurrences(of: "\\u0026", with: "&")
        }
        return nil
    }
}
