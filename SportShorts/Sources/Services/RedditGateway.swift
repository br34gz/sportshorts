import Foundation

/// Single choke-point for every reddit.com request. Token-bucket rate
/// limits, browser UA, 429 backoff. The doc's most important line: this
/// exists so that if Reddit changes policy or bans our UA, we have one
/// spot to fix.
actor RedditGateway {

    static let shared = RedditGateway()

    /// Token bucket: 30 capacity, 0.5 refill/sec (= 30 req/min sustained).
    /// Reddit's unauth guidance is ~60/min per IP; we halve for headroom.
    private var tokens: Double = 30
    private let capacity: Double = 30
    private let refillRatePerSecond: Double = 0.5
    private var lastRefill: Date = Date()
    /// Set when Reddit returns 429. Requests wait until this passes.
    private var backoffUntil: Date?

    /// Reddit blocks the default `CFNetwork/…` UA specifically. This UA
    /// identifies the app + platform, per Reddit's stated API etiquette.
    private let userAgent = "ios:sportshorts:v1.2 (unofficial iOS aggregator)"

    /// Fetch a Reddit endpoint (path relative to reddit.com or a full URL),
    /// return parsed JSON. Caller owns interpretation.
    func fetch(url: URL) async throws -> [String: Any] {
        try await waitForToken()

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Error.badResponse
        }

        if http.statusCode == 429 {
            // Respect the X-Ratelimit-Reset header when present, else 60s.
            let reset: TimeInterval = {
                if let s = http.value(forHTTPHeaderField: "X-Ratelimit-Reset"),
                   let n = TimeInterval(s), n > 0 { return n }
                return 60
            }()
            backoffUntil = Date(timeIntervalSinceNow: reset)
            throw Error.rateLimited
        }
        if http.statusCode == 403 || http.statusCode == 404 {
            throw Error.unavailable(status: http.statusCode)
        }
        guard http.statusCode == 200 else {
            throw Error.badStatus(http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.badResponse
        }
        return root
    }

    private func waitForToken() async throws {
        if let until = backoffUntil, until > Date() {
            let wait = until.timeIntervalSinceNow
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            backoffUntil = nil
        }
        refill()
        if tokens >= 1 {
            tokens -= 1
            return
        }
        // Wait until the next token is available.
        let needed = 1 - tokens
        let wait = needed / refillRatePerSecond
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        refill()
        tokens = max(0, tokens - 1)
    }

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(capacity, tokens + elapsed * refillRatePerSecond)
        lastRefill = now
    }

    enum Error: LocalizedError {
        case rateLimited
        case unavailable(status: Int)
        case badStatus(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .rateLimited:            return "Reddit rate-limited us — will retry."
            case .unavailable(let s):     return "Subreddit unavailable (HTTP \(s))."
            case .badStatus(let s):       return "Reddit returned HTTP \(s)."
            case .badResponse:            return "Unexpected Reddit response."
            }
        }
    }
}
