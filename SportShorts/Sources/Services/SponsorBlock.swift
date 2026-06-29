import Foundation

/// Lightweight client for the SponsorBlock community API (https://sponsor.ajay.app).
/// Returns skip ranges (in seconds) for the given YouTube video ID so the iframe
/// player can leap past sponsor / intro / outro / self-promo segments.
enum SponsorBlock {

    /// Categories we ask the server to return. Sports highlight videos commonly have
    /// broadcaster intro/outro bumpers (SBS, NRL etc) and sponsor reads.
    private static let categories = ["sponsor", "selfpromo", "intro", "outro", "interaction", "music_offtopic"]

    struct Segment: Codable {
        let segment: [Double]      // [start, end] in seconds
        let category: String
        let actionType: String     // "skip" | "mute" | "poi" — we only use skip
    }

    static func fetchSkipRanges(videoId: String) async -> [[Double]] {
        let cats = (try? String(data: JSONEncoder().encode(categories), encoding: .utf8)) ?? "[]"
        let escaped = cats.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cats
        let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=\(escaped)")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            // SponsorBlock returns 404 with empty body when no segments exist — that's fine, not an error.
            if let http = response as? HTTPURLResponse, http.statusCode == 404 { return [] }
            let segments = try JSONDecoder().decode([Segment].self, from: data)
            return segments
                .filter { $0.actionType == "skip" && $0.segment.count == 2 }
                .map { $0.segment }
        } catch {
            return []
        }
    }
}
