import CryptoKit
import Foundation
import Security

/// The My Nintendo / Nintendo Store app backend: the play-history channel that takes
/// a plain Nintendo Account token. Unlike the Nintendo Switch Online (Coral) API there
/// is no f parameter and no third-party service anywhere in the chain — the account
/// token Nintendo issues during the browser sign-in is the only credential involved.
enum NintendoAPI {
    private static let accountsURL = "https://accounts.nintendo.com"
    // clientID is the My Nintendo account application, which is what the play
    // history is scoped to. The redirect scheme is derived from it.
    private static let clientID = "5c38e31cd085304b"
    private static let appURL = "https://app-api.znej.nintendo.com"
    // Nintendo's gateway rejects a request without the app's own user agent.
    private static let userAgent = "com.nintendo.znej/3.0.3 (iOS/26.0.1)"
    // Required: without it the API answers 400 rather than picking a default.
    private static let locale = "en-GB"

    static var callbackURLScheme: String { "npf" + clientID }

    struct LoginRequest: Sendable {
        let url: URL
        let state: String
        let codeVerifier: String
    }

    struct LoginCode: Sendable {
        let code: String
        let verifier: String
    }

    struct Sync: Sendable {
        let games: [NintendoGame]
        let accountName: String?
        let avatarURL: URL?
        // The durable credential. A fresh login hands back a new one; the caller
        // stores it, since it is what every later sync is derived from.
        let sessionToken: String
    }

    // MARK: Sign-in

    /// The browser sign-in URL plus the PKCE secret behind its challenge.
    static func makeLoginRequest() -> LoginRequest {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let verifier = base64URL(randomBytes(32))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = base64URL(randomBytes(36))
        var components = URLComponents(string: accountsURL + "/connect/1.0.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: "npf" + clientID + "://auth"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: "openid user user.mii user.email user.links[].id"),
            URLQueryItem(name: "response_type", value: "session_token_code"),
            URLQueryItem(name: "session_token_code_challenge", value: challenge),
            URLQueryItem(name: "session_token_code_challenge_method", value: "S256"),
            URLQueryItem(name: "theme", value: "login_form"),
        ]
        return LoginRequest(url: components.url!, state: state, codeVerifier: verifier)
    }

    /// The sign-in ends on `npf<clientID>://auth#session_token_code=…&state=…`; the
    /// code lives in the fragment because Nintendo never hosts that page anywhere.
    static func sessionTokenCode(from url: URL, expectedState: String) throws -> String {
        guard url.scheme?.lowercased() == callbackURLScheme,
              url.host?.lowercased() == "auth",
              let fragment = url.fragment, !fragment.isEmpty
        else { throw NintendoError.invalidCallback }

        let items = fragment.split(separator: "&").reduce(into: [String: String]()) { partial, pair in
            let keyAndValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard keyAndValue.count == 2 else { return }
            partial[String(keyAndValue[0])] = keyAndValue[1].removingPercentEncoding
        }
        guard items["state"] == expectedState, !expectedState.isEmpty,
              let code = nonempty(items["session_token_code"])
        else { throw NintendoError.invalidCallback }
        return code
    }

    // MARK: Sync

    static func load(savedSessionToken: String?, login: LoginCode?) async throws -> Sync {
        try Task.checkCancellation()
        let sessionToken: String
        if let login {
            sessionToken = try await exchangeSessionToken(code: login.code, verifier: login.verifier)
        } else if let savedSessionToken, !savedSessionToken.isEmpty {
            sessionToken = savedSessionToken
        } else {
            throw NintendoError.missingSession
        }
        try Task.checkCancellation()

        let tokens = try await deriveTokens(sessionToken: sessionToken)

        // The nickname and avatar are presentation only; the history never
        // depends on them.
        let profile: (name: String?, avatar: URL?)?
        do {
            profile = try await accountProfile(accessToken: tokens.access_token)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            profile = nil
        }

        // The API takes either token and rejects one or the other as Nintendo
        // rotates their gateway; try the id token first and fall back once.
        let games: [NintendoGame]
        do {
            games = try await playHistories(bearer: tokens.id_token)
        } catch let error as NintendoError where error == .expiredSession {
            games = try await playHistories(bearer: tokens.access_token)
        }
        return Sync(games: games, accountName: profile?.name, avatarURL: profile?.avatar, sessionToken: sessionToken)
    }

    // MARK: Requests

    private struct SessionTokenResponse: Decodable {
        let session_token: String
    }

    private struct ServiceTokens: Decodable {
        let access_token: String
        let id_token: String
    }

    private struct AccountProfile: Decodable {
        let nickname: String?
        let iconUri: String?
    }

    private struct PlayHistoriesResponse: Decodable {
        let playHistories: [PlayHistory]
        let recentPlayHistories: [RecentPlayHistory]?
    }

    private struct PlayHistory: Decodable {
        let titleId: String
        let titleName: String
        let platform: String?
        let imageUrl: String?
        let firstPlayedAt: String?
        let lastPlayedAt: String?
        let totalPlayedMinutes: Int?
    }

    private struct RecentPlayHistory: Decodable {
        let playedDate: String?
        let dailyPlayHistories: [DailyPlayRecord]?
    }

    private struct DailyPlayRecord: Decodable {
        let titleId: String?
        let totalPlayedMinutes: Int?
    }

    private static func exchangeSessionToken(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: accountsURL + "/connect/1.0.0/api/session_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = [
            "client_id": clientID,
            "session_token_code": code,
            "session_token_code_verifier": verifier,
        ]
        .sorted { $0.key < $1.key }
        .map { formEncoded($0.key) + "=" + formEncoded($0.value) }
        .joined(separator: "&")
        .data(using: .utf8)
        let response: SessionTokenResponse = try await decode(request)
        guard let token = nonempty(response.session_token) else { throw NintendoError.badResponse }
        return token
    }

    private static func deriveTokens(sessionToken: String) async throws -> ServiceTokens {
        var request = URLRequest(url: URL(string: accountsURL + "/connect/1.0.0/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "session_token": sessionToken,
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer-session-token",
        ])
        return try await decode(request)
    }

    private static func accountProfile(accessToken: String) async throws -> (name: String?, avatar: URL?) {
        var request = URLRequest(url: URL(string: "https://api.accounts.nintendo.com/2.0.0/users/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let profile: AccountProfile = try await decode(request)
            return (nonempty(profile.nickname), nonempty(profile.iconUri).flatMap(URL.init(string:)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (nil, nil)
        }
    }

    private static func playHistories(bearer: String) async throws -> [NintendoGame] {
        var request = URLRequest(url: URL(string: appURL + "/api/v2.0/users/me/play_histories")!)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(locale, forHTTPHeaderField: "Gentry-Locale")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: PlayHistoriesResponse = try await decode(request)

        // The two-week column is derived from the daily records the API ships
        // alongside the totals; whatever window they cover is what we sum.
        var fortnight: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let cutoff = formatter.string(from: Date(timeIntervalSinceNow: -14 * 86_400))
        for day in response.recentPlayHistories ?? [] {
            guard let playedDate = day.playedDate, String(playedDate.prefix(10)) >= cutoff else { continue }
            for record in day.dailyPlayHistories ?? [] {
                guard let titleId = nonempty(record.titleId) else { continue }
                fortnight[titleId, default: 0] += max(record.totalPlayedMinutes ?? 0, 0)
            }
        }

        return response.playHistories.compactMap { entry in
            guard let name = nonempty(entry.titleName) else { return nil }
            return NintendoGame(
                name: name,
                imageUri: entry.imageUrl ?? "",
                shopUri: "",
                totalPlayTime: max(entry.totalPlayedMinutes ?? 0, 0),
                firstPlayedAt: unixSeconds(entry.firstPlayedAt),
                lastPlayedAt: unixSeconds(entry.lastPlayedAt),
                fortnightMinutes: fortnight[entry.titleId] ?? 0,
                titleId: nonempty(entry.titleId)
            )
        }
    }

    // MARK: Plumbing

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    private static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NintendoError.badResponse }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw NintendoError.unavailable
        } catch let error as NintendoError {
            throw error
        } catch {
            throw NintendoError.unavailable
        }
    }

    private static func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, http) = try await data(for: request)
        guard (200..<300).contains(http.statusCode) else { throw responseError(http.statusCode) }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw NintendoError.badResponse }
        return value
    }

    private static func responseError(_ status: Int) -> NintendoError {
        switch status {
        case 401, 403: .expiredSession
        case 429: .rateLimited
        case 500...599: .serviceUnavailable
        default: .requestFailed
        }
    }

    private static func formEncoded(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2A, 0x2D, 0x2E, 0x5F:
                String(UnicodeScalar(byte))
            case 0x20:
                "+"
            default:
                String(format: "%%%02X", Int(byte))
            }
        }.joined()
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unixSeconds(_ iso: String?) -> Int {
        guard let iso else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return 0 }
        return Int(date.timeIntervalSince1970)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(status == errSecSuccess)
        return data
    }
}

enum NintendoError: LocalizedError {
    case missingSession, expiredSession, unavailable, serviceUnavailable, badResponse
    case requestFailed, rateLimited, invalidCallback

    var errorDescription: String? {
        switch self {
        case .missingSession: L10n.tr("请先登录 Nintendo 账号")
        case .expiredSession: L10n.tr("Nintendo 会话已过期或无效，请重新登录")
        case .unavailable: L10n.tr("无法连接 Nintendo，请检查网络后重试")
        case .serviceUnavailable: L10n.tr("Nintendo 服务暂时不可用，请稍后重试")
        case .badResponse: L10n.tr("Nintendo 返回的数据格式无法读取")
        case .requestFailed: L10n.tr("Nintendo 请求失败，请稍后重试")
        case .rateLimited: L10n.tr("Nintendo 请求过于频繁，请稍后重试")
        case .invalidCallback: L10n.tr("Nintendo 登录回调验证失败，请重新登录")
        }
    }
}
