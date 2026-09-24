import Foundation

struct SteamGame: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let lifetimeMinutes: Int
    let fortnightMinutes: Int
}

struct SteamLibrary: Codable, Sendable {
    let games: [SteamGame]
    let recent: [SteamGame]

    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
    var fortnightMinutes: Int { recent.reduce(0) { $0 + $1.fortnightMinutes } }
}

struct SteamSnapshot: Codable, Sendable {
    let library: SteamLibrary
    let syncedAt: Date
}

enum LocalSnapshotStore {
    private static func file(_ name: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "Hourcade", directoryHint: .isDirectory).appending(path: name + ".json")
    }

    static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as name: String) throws {
        guard let url = file(name) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

enum SteamAPI {
    private struct GamesEnvelope: Decodable {
        let response: GamesResponse
    }
    private struct GamesResponse: Decodable {
        let games: [GameDTO]?
    }
    private struct GameDTO: Decodable {
        let appid: Int
        let name: String?
        let playtime_forever: Int?
        let playtime_2weeks: Int?
    }
    private struct VanityEnvelope: Decodable {
        let response: VanityResponse
    }
    private struct VanityResponse: Decodable {
        let success: Int
        let steamid: String?
    }

    static func load(account: String, key: String) async throws -> SteamLibrary {
        let steamID = try await resolveSteamID(account, key: key)
        let owned: GamesEnvelope = try await get(
            "/IPlayerService/GetOwnedGames/v1/",
            key: key,
            parameters: ["steamid": steamID, "include_appinfo": "true", "include_played_free_games": "true"]
        )
        let recent: GamesEnvelope = try await get(
            "/IPlayerService/GetRecentlyPlayedGames/v1/",
            key: key,
            parameters: ["steamid": steamID, "count": "100"]
        )
        let all = (owned.response.games ?? []).map {
            SteamGame(id: $0.appid, name: $0.name ?? "App \($0.appid)", lifetimeMinutes: $0.playtime_forever ?? 0, fortnightMinutes: $0.playtime_2weeks ?? 0)
        }
        let names = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })
        let latest = (recent.response.games ?? []).map {
            SteamGame(id: $0.appid, name: $0.name ?? names[$0.appid] ?? "App \($0.appid)", lifetimeMinutes: $0.playtime_forever ?? 0, fortnightMinutes: $0.playtime_2weeks ?? 0)
        }
        return SteamLibrary(games: all, recent: latest)
    }

    private static func resolveSteamID(_ raw: String, key: String) async throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count == 17, value.allSatisfy(\.isNumber) { return value }
        guard let url = URL(string: value), let host = url.host?.lowercased(),
              host == "steamcommunity.com" || host == "www.steamcommunity.com"
        else { throw SteamError.invalidAccount }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { throw SteamError.invalidAccount }
        if parts[0] == "profiles", parts[1].count == 17, parts[1].allSatisfy(\.isNumber) {
            return parts[1]
        }
        guard parts[0] == "id" else { throw SteamError.invalidAccount }
        let resolved: VanityEnvelope = try await get(
            "/ISteamUser/ResolveVanityURL/v1/",
            key: key,
            parameters: ["vanityurl": parts[1]]
        )
        guard resolved.response.success == 1, let id = resolved.response.steamid else {
            throw SteamError.vanityNotFound
        }
        return id
    }

    private static func get<T: Decodable & Sendable>(
        _ path: String,
        key: String,
        parameters: [String: String]
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.steampowered.com"
        components.path = path
        components.queryItems = ([URLQueryItem(name: "key", value: key)] +
            parameters.map { URLQueryItem(name: $0.key, value: $0.value) })
        guard let url = components.url else { throw SteamError.invalidURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SteamError.invalidResponse }
        guard http.statusCode == 200 else { throw SteamError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SteamError.invalidResponse
        }
    }
}

private enum SteamError: LocalizedError {
    case invalidAccount, vanityNotFound, invalidURL, invalidResponse, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAccount: "请输入 17 位 SteamID 或 steamcommunity.com 个人资料链接"
        case .vanityNotFound: "无法解析这个 Steam 个人资料链接"
        case .invalidURL: "无法构造 Steam API 请求"
        case .invalidResponse: "Steam 返回的数据格式无法读取"
        case .http(let code): "Steam API 请求失败（HTTP \(code)）；请检查密钥和资料隐私设置"
        }
    }
}
