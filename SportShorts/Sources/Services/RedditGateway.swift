import Foundation
import UIKit

/// Single choke-point for every reddit.com request. Handles the OAuth2
/// bearer-token dance, token caching, rate limiting, and 401/429 recovery.
///
/// Reddit closed unauth `.json` access. Users must supply an OAuth
/// **client_id** (and optionally a **client_secret**) from a Reddit app
/// they registered at reddit.com/prefs/apps.
actor RedditGateway {

    static let shared = RedditGateway()

    private struct Token { let value: String; let expiresAt: Date }
    private var token: Token?

    // Token bucket for rate limiting — 30 req/min sustained (half the
    // official 60/min guidance for authenticated apps for safety headroom).
    private var tokens: Double = 30
    private let capacity: Double = 30
    private let refillRatePerSecond: Double = 0.5
    private var lastRefill: Date = Date()
    private var backoffUntil: Date?

    private let userAgent = "ios:sportshorts:v1.2 (unofficial iOS aggregator)"

    /// Fetch a Reddit resource — pass the path like "/r/soccer/hot?limit=50".
    /// Auto-refreshes the bearer token on 401.
    func fetch(path: String, credentials: RedditCredentials) async throws -> [String: Any] {
        try await waitForToken()
        try await ensureAuthenticated(with: credentials)

        // All API calls use oauth.reddit.com when authenticated (not www).
        let url = URL(string: "https://oauth.reddit.com\(path)\(path.contains("?") ? "&" : "?")raw_json=1")!
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("bearer \(token.value)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }

        if http.statusCode == 401 {
            // Token expired — reauth once and retry.
            token = nil
            try await ensureAuthenticated(with: credentials)
            return try await fetch(path: path, credentials: credentials)
        }
        if http.statusCode == 429 {
            let reset: TimeInterval = {
                if let s = http.value(forHTTPHeaderField: "X-Ratelimit-Reset"), let n = TimeInterval(s), n > 0 { return n }
                return 60
            }()
            backoffUntil = Date(timeIntervalSinceNow: reset)
            throw Error.rateLimited
        }
        if http.statusCode == 403 || http.statusCode == 404 {
            throw Error.unavailable(status: http.statusCode)
        }
        guard http.statusCode == 200 else { throw Error.badStatus(http.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Error.badResponse }
        return root
    }

    // MARK: - OAuth

    /// Acquire a token if we don't have a fresh one. Uses Reddit's
    /// application-only OAuth ("installed_client" grant) — no user login,
    /// no username/password, just the client_id (and optionally secret).
    private func ensureAuthenticated(with credentials: RedditCredentials) async throws {
        if let token, token.expiresAt > Date().addingTimeInterval(60) { return }

        let clientId = credentials.clientId
        let clientSecret = credentials.clientSecret ?? ""
        let basicRaw = "\(clientId):\(clientSecret)"
        guard let basic = basicRaw.data(using: .utf8)?.base64EncodedString() else {
            throw Error.missingCredentials
        }

        // "DO_NOT_TRACK_THIS_DEVICE" is Reddit's documented opt-out identifier
        // for the device_id parameter — surfaces zero device analytics.
        let body = "grant_type=https%3A%2F%2Foauth.reddit.com%2Fgrants%2Finstalled_client&device_id=DO_NOT_TRACK_THIS_DEVICE"

        var req = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        req.httpMethod = "POST"
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        guard http.statusCode == 200 else {
            throw Error.authFailed(status: http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String else {
            throw Error.badResponse
        }
        let expiresIn = (root["expires_in"] as? Double) ?? 3600
        token = Token(value: access, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// Test the credentials by requesting a token. Used by the Settings UI
    /// to confirm the user's paste is valid.
    static func testCredentials(_ credentials: RedditCredentials) async throws {
        // Force a fresh token path — don't reuse cached bearer.
        await shared.forgetToken()
        try await shared.ensureAuthenticated(with: credentials)
    }

    private func forgetToken() { token = nil }

    // MARK: - Rate limiting

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
        case missingCredentials
        case authFailed(status: Int)

        var errorDescription: String? {
            switch self {
            case .rateLimited:            return "Reddit rate-limited us — will retry."
            case .unavailable(let s):     return "Subreddit unavailable (HTTP \(s))."
            case .badStatus(let s):       return "Reddit returned HTTP \(s)."
            case .badResponse:            return "Unexpected Reddit response."
            case .missingCredentials:     return "Reddit credentials not set. Add them in Settings → Sources."
            case .authFailed(let s):      return "Reddit rejected the client_id (HTTP \(s)). Double-check what you pasted."
            }
        }
    }
}

// MARK: - Credentials model

/// The user-supplied Reddit OAuth credentials. Empty client_id = not
/// configured. The secret is optional for "installed app" types.
struct RedditCredentials: Codable, Hashable {
    let clientId: String
    let clientSecret: String?

    var isConfigured: Bool { !clientId.isEmpty }
}
