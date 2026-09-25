import Foundation

enum PSNAPI {
    private static let authBase = "https://ca.account.sony.com/api/authz/v3/oauth"
    private static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    private static let redirectURI = "com.scee.psxandroid.scecompcall://redirect"
    private static let basic = "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="

    static var callbackURLScheme: String { URL(string: redirectURI)!.scheme! }

    static func authorizationURL(state: String) -> URL {
        var components = URLComponents(string: authBase + "/authorize")!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "psn:mobile.v2.core psn:clientapp"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    // Validates the exact scheme, host, path and state of the sign-in callback.
    static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let allowed = URLComponents(string: redirectURI)!
        guard let callback = URLComponents(url: url, resolvingAgainstBaseURL: false),
              callback.scheme?.lowercased() == allowed.scheme?.lowercased(),
              callback.host?.lowercased() == allowed.host?.lowercased(),
              callback.percentEncodedHost?.lowercased() == allowed.percentEncodedHost?.lowercased(),
              callback.percentEncodedPath.isEmpty || callback.percentEncodedPath == "/",
              callback.user == nil, callback.password == nil, callback.port == nil,
              callback.fragment == nil, !expectedState.isEmpty
        else { throw PSNError.invalidCallback }

        let items = callback.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        let errors = items.filter { $0.name == "error" }
        guard states.count == 1, states.first?.value == expectedState,
              codes.count <= 1, errors.count <= 1, codes.isEmpty || errors.isEmpty
        else { throw PSNError.invalidCallback }
        if let error = errors.first {
            guard let value = error.value, !value.isEmpty else { throw PSNError.invalidCallback }
            // Do not surface error_description or other untrusted service text.
            if value == "login_required" || value == "invalid_grant" {
                throw PSNError.expiredSession
            }
            throw PSNError.authorizationRejected
        }
        guard let code = codes.first?.value, !code.isEmpty else { throw PSNError.missingCode }
        return code
    }

    private struct Tokens: Decodable, Sendable {
        let access_token: String
        let refresh_token: String?
    }

    private struct OAuthFailure: Decodable {
        let error: String?
    }

    private struct GamesResponse: Decodable {
        let titles: [GameDTO]
        let totalItemCount: Int
        let nextOffset: Int?
    }

    private struct GameDTO: Decodable {
        let titleId: String
        let name: String
        let localizedName: String?
        let imageUrl: String?
        let localizedImageUrl: String?
        let playDuration: String?
        let lastPlayedDateTime: String?

        private enum CodingKeys: String, CodingKey {
            case titleId, name, localizedName, imageUrl, localizedImageUrl, playDuration, lastPlayedDateTime
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            titleId = try values.decode(String.self, forKey: .titleId)
            name = try values.decode(String.self, forKey: .name)
            localizedName = try? values.decode(String.self, forKey: .localizedName)
            imageUrl = try? values.decode(String.self, forKey: .imageUrl)
            localizedImageUrl = try? values.decode(String.self, forKey: .localizedImageUrl)
            // A missing, null, or incorrectly typed duration is unknown, not zero.
            playDuration = try? values.decode(String.self, forKey: .playDuration)
            lastPlayedDateTime = try values.decodeIfPresent(String.self, forKey: .lastPlayedDateTime)
        }
    }

    static func load(
        savedRefreshToken: String?,
        accessCode: String? = nil,
        saveRefreshToken: (@Sendable (String) throws -> Void)? = nil
    ) async throws -> (PSNLibrary, String?) {
        try Task.checkCancellation()

        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let tokens: Tokens
        if let accessCode {
            guard !accessCode.isEmpty else { throw PSNError.missingCode }
            tokens = try await token(parameters: [
                "code": accessCode,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "token_format": "jwt"
            ], session: session)
        } else if let savedRefreshToken, !savedRefreshToken.isEmpty {
            tokens = try await token(parameters: [
                "refresh_token": savedRefreshToken,
                "grant_type": "refresh_token",
                "token_format": "jwt",
                "scope": "psn:mobile.v2.core psn:clientapp"
            ], session: session)
        } else {
            throw PSNError.missingSession
        }

        // Persist rotation before cancellation checks or any fallible profile/library work.
        if let refreshToken = tokens.refresh_token {
            try saveRefreshToken?(refreshToken)
        }
        try Task.checkCancellation()

        // Always the signed-in account. The Online ID and avatar are display
        // labels, so a failed lookup must not fail the sync.
        let profile = await selfProfile(accessToken: tokens.access_token, session: session)
        let trophies = await selfTrophies(accessToken: tokens.access_token, session: session, accountID: profile.accountID)
        let accountID = "me"

        let limit = 100
        var games: [PSNGame] = []
        var seenTitleIDs = Set<String>()
        var expectedTotal: Int?
        var totalMinutes = 0
        var offset = 0
        // A safety bound is a failure, never a successful but truncated snapshot.
        for _ in 0..<1_000 {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://m.np.playstation.com/api/gamelist/v2/users/\(accountID)/titles")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
            let page: GamesResponse = try await decode(request, session: session)
            guard page.totalItemCount >= 0, page.titles.count <= limit,
                  expectedTotal == nil || expectedTotal == page.totalItemCount
            else { throw PSNError.incompleteLibrary }
            expectedTotal = page.totalItemCount
            let (endOffset, overflow) = offset.addingReportingOverflow(page.titles.count)
            guard !overflow, endOffset <= page.totalItemCount else { throw PSNError.incompleteLibrary }
            if endOffset < page.totalItemCount, let next = page.nextOffset {
                guard next == endOffset else { throw PSNError.incompleteLibrary }
            }

            for title in page.titles {
                guard !title.titleId.isEmpty, seenTitleIDs.insert(title.titleId).inserted
                else { throw PSNError.incompleteLibrary }
                let minutes = title.playDuration.flatMap(durationMinutes)
                let (sum, overflow) = totalMinutes.addingReportingOverflow(minutes ?? 0)
                guard !overflow else { throw PSNError.badResponse }
                totalMinutes = sum
                let name = nonempty(title.localizedName) ?? nonempty(title.name)
                guard let name else { throw PSNError.badResponse }
                var game = PSNGame(
                    id: title.titleId,
                    name: name,
                    lifetimeMinutes: minutes ?? 0,
                    lastPlayed: title.lastPlayedDateTime
                )
                game.imageURL = imageURL(title.localizedImageUrl) ?? imageURL(title.imageUrl)
                game.hasPlaytime = minutes != nil
                games.append(game)
            }

            if endOffset == page.totalItemCount {
                guard games.count == page.totalItemCount else { throw PSNError.incompleteLibrary }
                var library = PSNLibrary(games: games)
                library.onlineID = profile.onlineID
                library.avatarURL = profile.avatar
                library.trophies = trophies
                return (library, tokens.refresh_token)
            }
            guard !page.titles.isEmpty else { throw PSNError.incompleteLibrary }
            offset = page.nextOffset ?? endOffset
        }
        throw PSNError.incompleteLibrary
    }

    // Display-only labels for the signed-in account. Any failure (privacy,
    // network, unexpected shape) resolves to nil and leaves the sync unaffected.
    private static func selfProfile(accessToken: String, session: URLSession) async -> (onlineID: String?, avatar: URL?, accountID: String?) {
        var components = URLComponents(string: "https://us-prof.np.community.playstation.net/userProfile/v1/users/me/profile2")!
        components.queryItems = [URLQueryItem(name: "fields", value: "onlineId,accountId,avatarUrls")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, http) = try? await Self.data(for: request, session: session),
              (200..<300).contains(http.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profile = root["profile"] as? [String: Any] else { return (nil, nil, nil) }
        let onlineID = nonempty(profile["onlineId"] as? String)
        let accountID = nonempty(profile["accountId"] as? String)
        var avatar = bestAvatar(from: profile["avatarUrls"] as? [[String: Any]], urlKey: "avatarUrl")
        if avatar == nil, let onlineID {
            // The legacy host only attaches avatars when addressed by online id.
            var byName = URLRequest(url: URL(string: "https://us-prof.np.community.playstation.net/userProfile/v1/users/\(onlineID)/profile2?fields=avatarUrls")!)
            byName.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let (data, http) = try? await Self.data(for: byName, session: session),
               (200..<300).contains(http.statusCode),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let profile2 = root["profile"] as? [String: Any] {
                avatar = bestAvatar(from: profile2["avatarUrls"] as? [[String: Any]], urlKey: "avatarUrl")
            }
        }
        if avatar == nil {
            // The modern endpoint needs a different token class and rejects ours;
            // kept only as the last resort, tolerated to fail.
            var modern = URLRequest(url: URL(string: "https://m.np.playstation.com/api/userProfile/v1/internal/users/me/profile2")!)
            modern.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let (data, http) = try? await Self.data(for: modern, session: session),
               (200..<300).contains(http.statusCode),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                avatar = bestAvatar(from: root["avatarUrls"] as? [[String: Any]], urlKey: "avatarUrl")
                    ?? bestAvatar(from: root["profilePictureUrls"] as? [[String: Any]], urlKey: "profilePictureUrl")
            }
        }
        return (onlineID, avatar, accountID)
    }

    private static func bestAvatar(from entries: [[String: Any]]?, urlKey: String) -> URL? {
        guard let entries else { return nil }
        // The default avatar is served over plain http, which ATS would block;
        // the host supports https, so upgrade the scheme before validating.
        let urls = entries.compactMap { ($0[urlKey] as? String)?.replacingOccurrences(of: "http://", with: "https://") }
        // The renditions' ordering is unspecified; prefer the extra-large one.
        return (urls.first { $0.lowercased().contains("xl") } ?? urls.last).flatMap(imageURL)
    }

    // Account-level trophy numbers are presentation only; any failure resolves
    // to nil and leaves the library sync unaffected.
    private static func selfTrophies(accessToken: String, session: URLSession, accountID: String?) async -> PSNTrophies? {
        var result = PSNTrophies()
        var summaryAccountId: String?

        var summaryRequest = URLRequest(url: URL(string: "https://m.np.playstation.com/api/trophy/v1/users/me/trophySummary")!)
        summaryRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let summary: TrophySummaryDTO = try? await decode(summaryRequest, session: session) {
            summaryAccountId = nonempty(summary.accountId)
            result.level = summary.trophyLevel?.value
            result.earned.bronze = summary.earnedTrophies?.bronze ?? 0
            result.earned.silver = summary.earnedTrophies?.silver ?? 0
            result.earned.gold = summary.earnedTrophies?.gold ?? 0
            result.earned.platinum = summary.earnedTrophies?.platinum ?? 0
        }

        // The completion rate is the sum over every trophy title the account
        // owns: earned ÷ defined. This endpoint needs the numeric account id;
        // "me" is only accepted by the summary above.
        let id = nonempty(accountID) ?? summaryAccountId ?? "me"
        var earnedTotal = 0
        var definedTotal = 0
        var offset = 0
        let limit = 800
        for _ in 0..<50 {
            var components = URLComponents(string: "https://m.np.playstation.com/api/trophy/v1/users/\(id)/trophyTitles")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            guard let page: TrophyTitlesResponse = try? await decode(request, session: session),
                  let titles = page.trophyTitles, !titles.isEmpty else { break }
            for title in titles {
                earnedTotal += title.earnedTrophies?.total ?? 0
                definedTotal += title.definedTrophies?.total ?? 0
            }
            guard titles.count == limit else { break }
            offset += limit
        }
        result.earnedTotal = earnedTotal
        result.definedTotal = definedTotal
        return result
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: StopRedirect(), delegateQueue: nil)
    }

    private static func token(parameters: [String: String], session: URLSession) async throws -> Tokens {
        var request = URLRequest(url: URL(string: authBase + "/token")!)
        request.httpMethod = "POST"
        request.setValue(basic, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(formEncoded(key))=\(formEncoded(value))"
        }.joined(separator: "&").data(using: .utf8)
        let tokens: Tokens = try await decode(request, session: session, isTokenRequest: true)
        guard !tokens.access_token.isEmpty,
              tokens.access_token.utf8.allSatisfy({ (0x21...0x7E).contains($0) }),
              tokens.refresh_token == nil || tokens.refresh_token?.isEmpty == false
        else { throw PSNError.badResponse }
        return tokens
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

    private static func data(for request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PSNError.badResponse }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            // Never expose NSError userInfo, which may contain authenticated URLs.
            throw PSNError.unavailable
        } catch let error as PSNError {
            throw error
        } catch {
            throw PSNError.unavailable
        }
    }

    private static func decode<T: Decodable>(
        _ request: URLRequest,
        session: URLSession,
        isTokenRequest: Bool = false
    ) async throws -> T {
        let (data, http) = try await Self.data(for: request, session: session)
        guard (200..<300).contains(http.statusCode) else {
            if isTokenRequest, http.statusCode == 400,
               let failure = try? JSONDecoder().decode(OAuthFailure.self, from: data),
               failure.error == "invalid_grant" || failure.error == "invalid_token" {
                throw PSNError.expiredSession
            }
            throw responseError(http.statusCode)
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw PSNError.badResponse }
        return value
    }

    private static func responseError(_ status: Int) -> PSNError {
        switch status {
        case 401: .expiredSession
        case 403: .privateLibrary
        case 429: .rateLimited
        case 500...599: .serviceUnavailable
        default: .requestFailed
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func imageURL(_ value: String?) -> URL? {
        guard let value = nonempty(value), let url = URL(string: value),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    private static func durationMinutes(_ iso: String) -> Int? {
        let pattern = /P(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+(?:[.,][0-9]+)?)S)?)?/
        guard let match = iso.wholeMatch(of: pattern),
              match.1 != nil || match.2 != nil || match.3 != nil || match.4 != nil,
              !iso.contains("T") || match.2 != nil || match.3 != nil || match.4 != nil
        else { return nil }
        func number(_ value: Substring?) -> Double {
            guard let value else { return 0 }
            return Double(value.replacingOccurrences(of: ",", with: ".")) ?? .infinity
        }
        let seconds = number(match.1) * 86_400 + number(match.2) * 3_600
            + number(match.3) * 60 + number(match.4)
        let minutes = (seconds / 60).rounded()
        guard minutes.isFinite, minutes >= 0, minutes < Double(Int.max) else { return nil }
        return Int(minutes)
    }
}

// MARK: - Lazy per-game trophy lookups

extension PSNAPI {
    /// A fresh access token for out-of-sync lookups (the lazy trophy rows).
    static func accessToken(savedRefreshToken: String?) async -> String? {
        guard let savedRefreshToken, !savedRefreshToken.isEmpty else { return nil }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        guard let tokens = try? await token(parameters: [
            "refresh_token": savedRefreshToken,
            "grant_type": "refresh_token",
            "token_format": "jwt",
            "scope": "psn:mobile.v2.core psn:clientapp"
        ], session: session) else { return nil }
        return tokens.access_token
    }

    static func titleTrophies(
        titleId: String,
        accessToken: String,
        session: URLSession
    ) async -> (bronze: Int, silver: Int, gold: Int, platinum: Int, defined: Int, progress: Int)? {
        var components = URLComponents(string: "https://m.np.playstation.com/api/trophy/v1/users/me/titles/trophyTitles")!
        components.queryItems = [URLQueryItem(name: "npTitleIds", value: titleId)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let page: TitleTrophiesResponse = try? await decode(request, session: session) else { return nil }
        if let trophyTitle = page.titles?.first?.trophyTitles?.first, let defined = trophyTitle.definedTrophies {
            let earned = trophyTitle.earnedTrophies
            return (
                bronze: earned?.bronze ?? 0,
                silver: earned?.silver ?? 0,
                gold: earned?.gold ?? 0,
                platinum: earned?.platinum ?? 0,
                defined: defined.total,
                progress: trophyTitle.progress ?? 0
            )
        }
        // The account owns the game but has no trophy data for it; cache the
        // zero so the row never re-requests.
        return (bronze: 0, silver: 0, gold: 0, platinum: 0, defined: 0, progress: 0)
    }

    private struct TrophyTitlesResponse: Decodable {
        // The account-level list nests its items under `trophyTitles`, unlike
        // the per-title lookup which uses `titles`.
        let trophyTitles: [TrophyTitleDTO]?
        let totalItemCount: Int?
        let nextOffset: Int?
    }

    private struct TitleTrophiesResponse: Decodable {
        let titles: [GameTitleEntry]?
    }

    private struct GameTitleEntry: Decodable {
        let trophyTitles: [TrophyTitleDTO]?
    }

    private struct TrophyTitleDTO: Decodable {
        let progress: Int?
        let earnedTrophies: TrophyCountsDTO?
        let definedTrophies: TrophyCountsDTO?
    }

    private struct TrophyCountsDTO: Decodable {
        let bronze: Int?
        let silver: Int?
        let gold: Int?
        let platinum: Int?

        var total: Int { (bronze ?? 0) + (silver ?? 0) + (gold ?? 0) + (platinum ?? 0) }
    }

    private struct TrophySummaryDTO: Decodable {
        let accountId: String?
        let trophyLevel: FlexibleInt?
        let earnedTrophies: TrophyCountsDTO?
    }
}

/// PSN reports the trophy level as a number in the API docs but as a string in
/// some deployments; accept both.
private struct FlexibleInt: Decodable, Sendable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self), let int = Int(string) {
            value = int
        } else {
            throw DecodingError.valueNotFound(
                Int.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected an integer")
            )
        }
    }
}

/// Lazy per-game trophy lookups with a day-long disk cache; the platform page
/// fetches one row at a time so syncing never depends on this.
actor PSNTrophyStore {
    static let shared = PSNTrophyStore()

    struct Entry: Codable, Sendable {
        let bronze: Int
        let silver: Int
        let gold: Int
        let platinum: Int
        let defined: Int
        let progress: Int
        let fetchedAt: Date

        var total: Int { bronze + silver + gold + platinum }
    }

    private var cache: [String: Entry]?
    private var token: (value: String, fetchedAt: Date)?

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "Hourcade/psn-trophies.json")
    }

    func summary(titleId: String) async -> Entry? {
        await loadFromDisk()
        if let entry = cache?[titleId], Date().timeIntervalSince(entry.fetchedAt) < 86_400 {
            return entry
        }
        guard let accessToken = await currentToken() else { return nil }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let result = await PSNAPI.titleTrophies(titleId: titleId, accessToken: accessToken, session: session) else { return nil }
        let entry = Entry(
            bronze: result.bronze,
            silver: result.silver,
            gold: result.gold,
            platinum: result.platinum,
            defined: result.defined,
            progress: result.progress,
            fetchedAt: .now
        )
        cache?[titleId] = entry
        persist()
        return entry
    }

    private func currentToken() async -> String? {
        if let token, Date().timeIntervalSince(token.fetchedAt) < 3_000 { return token.value }
        guard let value = await PSNAPI.accessToken(savedRefreshToken: KeychainSecret.read("psn.refreshToken")) else { return nil }
        token = (value, .now)
        return value
    }

    private func loadFromDisk() {
        guard cache == nil else { return }
        guard let file = Self.file, let data = try? Data(contentsOf: file) else {
            cache = [:]
            return
        }
        cache = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func persist() {
        guard let file = Self.file, let cache, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

// No redirect is followed automatically, so credentials cannot cross origins.
private final class StopRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum PSNError: LocalizedError {
    case missingSession, expiredSession, privateLibrary
    case rateLimited, unavailable, serviceUnavailable, badResponse, requestFailed, incompleteLibrary
    case invalidCallback, authorizationRejected, missingCode

    var errorDescription: String? {
        switch self {
        case .missingSession: L10n.tr("请先登录 PlayStation 账号")
        case .expiredSession: L10n.tr("PlayStation 会话已过期或无效，请重新登录")
        case .privateLibrary: L10n.tr("无法访问 PSN 游戏列表，请检查账号的隐私设置或访问权限")
        case .rateLimited: L10n.tr("PSN 请求过于频繁，请稍后重试")
        case .unavailable: L10n.tr("无法连接 PlayStation，请检查网络后重试")
        case .serviceUnavailable: L10n.tr("PlayStation 服务暂时不可用，请稍后重试")
        case .badResponse: L10n.tr("PSN 返回的数据格式无法读取")
        case .requestFailed: L10n.tr("PSN 请求失败，请稍后重试")
        case .incompleteLibrary: L10n.tr("PSN 游戏列表分页不完整或已变化，请重新同步")
        case .invalidCallback: L10n.tr("PlayStation 登录回调验证失败，请重新登录")
        case .authorizationRejected: L10n.tr("PlayStation 未授予授权，请重新登录并允许访问")
        case .missingCode: L10n.tr("PlayStation 登录完成，但没有返回授权码")
        }
    }
}
