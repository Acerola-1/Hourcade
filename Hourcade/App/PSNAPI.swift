import Foundation

struct PSNGame: Identifiable, Sendable {
    let id: String
    let name: String
    let lifetimeMinutes: Int
    let lastPlayed: String?
}

struct PSNLibrary: Sendable {
    let games: [PSNGame]
    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
}

enum PSNAPI {
    private static let authBase = "https://ca.account.sony.com/api/authz/v3/oauth"
    private static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    private static let redirectURI = "com.scee.psxandroid.scecompcall://redirect"
    private static let basic = "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="

    private struct Tokens: Decodable, Sendable {
        let access_token: String
        let refresh_token: String?
    }
    private struct SearchResult: Decodable {
        let domainResponses: [SearchDomain]
    }
    private struct SearchDomain: Decodable {
        let results: [SearchItem]
    }
    private struct SearchItem: Decodable {
        let socialMetadata: SearchMetadata?
    }
    private struct SearchMetadata: Decodable {
        let accountId: String
        let onlineId: String
    }
    private struct GamesResponse: Decodable {
        let titles: [GameDTO]
        let totalItemCount: Int
    }
    private struct GameDTO: Decodable {
        let titleId: String
        let name: String
        let playDuration: String?
        let lastPlayedDateTime: String?
    }

    static func load(onlineID: String, npsso: String?, savedRefreshToken: String?) async throws -> (PSNLibrary, String?) {
        let tokens: Tokens
        if let npsso, !npsso.isEmpty {
            let code = try await accessCode(npsso)
            tokens = try await token(parameters: [
                "code": code,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "token_format": "jwt"
            ])
        } else if let savedRefreshToken {
            tokens = try await token(parameters: [
                "refresh_token": savedRefreshToken,
                "grant_type": "refresh_token",
                "token_format": "jwt",
                "scope": "psn:mobile.v2.core psn:clientapp"
            ])
        } else {
            throw PSNError.missingSession
        }

        let searchURL = URL(string: "https://m.np.playstation.com/api/search/v1/universalSearch")!
        var searchRequest = URLRequest(url: searchURL)
        searchRequest.httpMethod = "POST"
        searchRequest.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        searchRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        searchRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "searchTerm": onlineID,
            "domainRequests": [["domain": "SocialAllAccounts"]]
        ])
        let search: SearchResult = try await decode(searchRequest)
        guard let accountID = search.domainResponses.flatMap(\.results)
            .compactMap(\.socialMetadata)
            .first(where: { $0.onlineId.caseInsensitiveCompare(onlineID) == .orderedSame })?.accountId
        else { throw PSNError.accountNotFound }

        var games: [PSNGame] = []
        var offset = 0
        repeat {
            var components = URLComponents(string: "https://m.np.playstation.com/api/gamelist/v2/users/\(accountID)/titles")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
            let page: GamesResponse = try await decode(request)
            games += page.titles.map {
                PSNGame(
                    id: $0.titleId,
                    name: $0.name,
                    lifetimeMinutes: durationMinutes($0.playDuration ?? ""),
                    lastPlayed: $0.lastPlayedDateTime
                )
            }
            offset += page.titles.count
            if page.titles.isEmpty || offset >= page.totalItemCount { break }
        } while offset < 10_000
        return (PSNLibrary(games: games), tokens.refresh_token)
    }

    private static func accessCode(_ npsso: String) async throws -> String {
        var components = URLComponents(string: authBase + "/authorize")!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "psn:mobile.v2.core psn:clientapp")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")
        let session = URLSession(configuration: .ephemeral, delegate: StopRedirect(), delegateQueue: nil)
        let (_, response) = try await session.data(for: request)
        guard let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let code = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw PSNError.invalidSession }
        return code
    }

    private static func token(parameters: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: authBase + "/token")!)
        request.httpMethod = "POST"
        request.setValue(basic, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        return try await decode(request)
    }

    private static func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PSNError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw PSNError.http(http.statusCode) }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw PSNError.badResponse }
        return value
    }

    private static func durationMinutes(_ iso: String) -> Int {
        let pattern = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/
        guard let match = iso.firstMatch(of: pattern) else { return 0 }
        let h = Int(match.1 ?? "") ?? 0
        let m = Int(match.2 ?? "") ?? 0
        let s = Int(match.3 ?? "") ?? 0
        return h * 60 + m + (s >= 30 ? 1 : 0)
    }
}

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
    case missingSession, invalidSession, accountNotFound, badResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingSession: "请先提供 NPSSO 会话令牌"
        case .invalidSession: "无法换取 PSN 授权码；会话可能已过期"
        case .accountNotFound: "已认证，但未找到完全匹配的 PSN Online ID"
        case .badResponse: "PSN 返回的数据格式无法读取"
        case .http(let status): "PSN 请求失败（HTTP \(status)）；请检查会话及隐私设置"
        }
    }
}
