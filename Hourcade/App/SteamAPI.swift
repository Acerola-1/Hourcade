import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        let rtime_last_played: Int?
    }
    private struct VanityEnvelope: Decodable {
        let response: VanityResponse
    }
    private struct VanityResponse: Decodable {
        let success: Int
        let steamid: String?
    }
    private struct PlayersEnvelope: Decodable, Sendable {
        let response: PlayersResponse
    }
    private struct PlayersResponse: Decodable, Sendable {
        let players: [PlayerDTO]
    }
    private struct PlayerDTO: Decodable, Sendable {
        let steamid: String
        let personaname: String
        let avatarfull: String?
    }

    static func load(account: String, key: String) async throws -> SteamLibrary {
        let steamID = try await resolveSteamID(account, key: key)
        async let profile: PlayersEnvelope? = try? get(
            "/ISteamUser/GetPlayerSummaries/v2/",
            key: key,
            parameters: ["steamids": steamID]
        )
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
            SteamGame(id: $0.appid, name: $0.name ?? "App \($0.appid)", lifetimeMinutes: $0.playtime_forever ?? 0, fortnightMinutes: $0.playtime_2weeks ?? 0, lastPlayedAt: $0.rtime_last_played)
        }
        let names = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })
        let latest = (recent.response.games ?? []).map {
            SteamGame(id: $0.appid, name: $0.name ?? names[$0.appid] ?? "App \($0.appid)", lifetimeMinutes: $0.playtime_forever ?? 0, fortnightMinutes: $0.playtime_2weeks ?? 0, lastPlayedAt: $0.rtime_last_played)
        }
        let summary = await profile
        let player = summary?.response.players.first(where: { $0.steamid == steamID }).map { dto in
            let avatarURL = dto.avatarfull.flatMap { URL(string: $0) }.flatMap {
                isAllowedAvatarURL($0) ? $0 : nil
            }
            return SteamPlayer(name: dto.personaname, avatarURL: avatarURL)
        }
        return SteamLibrary(games: all, recent: latest, player: player)
    }

    private enum ArtworkJob: Sendable {
        case game(Int)
        case avatar(url: URL, name: String)
    }

    private enum ArtworkKind: Sendable {
        case hero, cover, avatar, header

        var maximumDimension: Int {
            switch self {
            case .hero: 1_920
            case .cover: 900
            case .avatar, .header: 1_000
            }
        }

        func accepts(width: Int, height: Int) -> Bool {
            guard width > 0, height > 0 else { return false }
            switch self {
            case .hero: return width >= 1_280 && height >= 400 && width > height
            // Steam's normal cover is 300x450; the preferred _2x asset is 600x900.
            case .cover: return width >= 300 && height >= 450 && height > width
            case .avatar, .header: return true
            }
        }
    }

    private struct StoreResponse: Decodable {
        let success: Bool
        let data: StoreDetails?
    }

    private struct StoreDetails: Decodable {
        let header_image: URL?
        let screenshots: [StoreScreenshot]?
    }

    private struct StoreScreenshot: Decodable {
        let path_full: URL?
    }

    private static let maximumArtworkBytes = 8 * 1_024 * 1_024
    private static let maximumStoreDetailsBytes = 2 * 1_024 * 1_024
    private static let maximumConcurrentArtworkJobs = 4

    static func cacheArtwork(for snapshot: SteamSnapshot) async {
        let recent = snapshot.library.recent
            .filter { $0.id > 0 && $0.fortnightMinutes > 0 }
            .sorted { $0.fortnightMinutes > $1.fortnightMinutes }
        var ids = Array(recent.prefix(6).map(\.id))
        if let favorite = snapshot.library.games.filter({ $0.id > 0 })
            .max(by: { $0.lifetimeMinutes < $1.lifetimeMinutes }) {
            ids.append(favorite.id)
        }
        var seen = Set<Int>()
        var jobs = ids.filter { seen.insert($0).inserted }.map { ArtworkJob.game($0) }
        if let player = snapshot.library.player, let url = player.avatarURL,
           let name = player.avatarName, isAllowedAvatarURL(url) {
            jobs.append(.avatar(url: url, name: name))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: ArtworkRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Six recent games plus one unique lifetime favorite and the avatar; four jobs total in flight.
        await withTaskGroup(of: Void.self) { group in
            var pending = jobs.makeIterator()
            for _ in 0..<maximumConcurrentArtworkJobs {
                guard !Task.isCancelled, let job = pending.next() else { break }
                group.addTask { await cacheArtwork(job, using: session) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let job = pending.next() {
                    group.addTask { await cacheArtwork(job, using: session) }
                }
            }
        }
    }

    private static func cacheArtwork(_ job: ArtworkJob, using session: URLSession) async {
        switch job {
        case .game(let appID):
            await cacheGameArtwork(for: appID, using: session)
        case .avatar(let url, let name):
            guard let destination = SteamWidgetStore.artworkURL(named: name),
                  !isValidCachedArtwork(at: destination, kind: .avatar)
            else { return }
            _ = await cacheImage(from: url, at: destination, kind: .avatar, using: session)
        }
    }

    private static func cacheGameArtwork(for appID: Int, using session: URLSession) async {
        guard !Task.isCancelled,
              let hero = SteamWidgetStore.artworkURL(named: "steam-\(appID)-hero-hd"),
              let cover = SteamWidgetStore.artworkURL(named: "steam-\(appID)-cover-hd"),
              let base = URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/")
        else { return }
        // Never treat a legacy 460x215 header as a successful HD cache hit.
        var hasHero = isValidCachedArtwork(at: hero, kind: .hero)
        var hasCover = isValidCachedArtwork(at: cover, kind: .cover)
        if !hasHero {
            hasHero = await cacheImage(from: base.appendingPathComponent("library_hero.jpg"), at: hero, kind: .hero, using: session)
        }
        if !hasCover {
            for filename in ["library_600x900_2x.jpg", "library_600x900.jpg"] {
                hasCover = await cacheImage(from: base.appendingPathComponent(filename), at: cover, kind: .cover, using: session)
                if hasCover || Task.isCancelled { break }
            }
        }
        guard !Task.isCancelled, !hasHero || !hasCover else { return }

        // Newer games may only expose hashed assets. Resolve public metadata once for both targets.
        guard let details = await storeDetails(for: appID, using: session) else { return }
        if !hasHero {
            var seen = Set<URL>()
            let screenshots = (details.screenshots ?? []).compactMap(\.path_full)
                .filter { isAllowedGameArtworkURL($0) && seen.insert($0).inserted }
            // Bound retries as well as bytes; verify actual resolution, not a filename's claim.
            for url in screenshots.prefix(3) {
                hasHero = await cacheImage(from: url, at: hero, kind: .hero, using: session)
                if hasHero || Task.isCancelled { break }
            }
        }
        guard !Task.isCancelled, !hasHero || !hasCover,
              let header = details.header_image, isAllowedGameArtworkURL(header),
              let legacy = SteamWidgetStore.artworkURL(named: "steam-\(appID)"),
              !isValidCachedArtwork(at: legacy, kind: .header)
        else { return }
        // Explicit last fallback only. Keep it separate so future syncs can still upgrade to HD.
        _ = await cacheImage(from: header, at: legacy, kind: .header, using: session)
    }

    private static func cacheImage(from url: URL, at destination: URL, kind: ArtworkKind, using session: URLSession) async -> Bool {
        guard !Task.isCancelled,
              kind == .avatar ? isAllowedAvatarURL(url) : isAllowedGameArtworkURL(url)
        else { return false }
        do {
            guard let data = try await boundedData(from: url, maximumBytes: maximumArtworkBytes, image: true, using: session),
                  let jpeg = downsampledJPEG(data, kind: kind)
            else { return false }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: destination, options: .atomic)
            return true
        } catch {
            // Artwork is optional. Never surface network URLs or fail the library sync.
            return false
        }
    }

    private static func storeDetails(for appID: Int, using session: URLSession) async -> StoreDetails? {
        guard !Task.isCancelled,
              let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)")
        else { return nil }
        do {
            guard let data = try await boundedData(from: url, maximumBytes: maximumStoreDetailsBytes, image: false, using: session),
                  let result = try JSONDecoder().decode([String: StoreResponse].self, from: data)[String(appID)], result.success
            else { return nil }
            return result.data
        } catch {
            return nil
        }
    }

    private static func boundedData(from url: URL, maximumBytes: Int, image: Bool, using session: URLSession) async throws -> Data? {
        try Task.checkCancellation()
        guard image ? isAllowedArtworkURL(url) : isAllowedStoreDetailsURL(url) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url,
              image ? isAllowedArtworkURL(finalURL) : isAllowedStoreDetailsURL(finalURL),
              image ? http.mimeType?.lowercased().hasPrefix("image/") == true : http.mimeType?.lowercased() == "application/json",
              http.expectedContentLength <= Int64(maximumBytes)
        else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { return nil }
            data.append(byte)
        }
        return data
    }

    private static func downsampledJPEG(_ data: Data, kind: ArtworkKind) -> Data? {
        guard !data.isEmpty, data.count <= maximumArtworkBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 32_000_000,
              kind.accepts(width: width, height: height)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: kind.maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              kind.accepts(width: image.width, height: image.height)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumArtworkBytes else { return nil }
        return output as Data
    }

    private static func isValidCachedArtwork(at url: URL, kind: ArtworkKind) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumArtworkBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              kind.accepts(width: width, height: height),
              width <= kind.maximumDimension, height <= kind.maximumDimension,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { return false }
        return CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    }

    private static func isAllowedAvatarURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        switch host {
        case "avatars.steamstatic.com", "avatars.akamai.steamstatic.com", "avatars.cloudflare.steamstatic.com":
            return true
        case "steamcdn-a.akamaihd.net", "cdn.akamai.steamstatic.com", "community.akamai.steamstatic.com":
            return url.path.hasPrefix("/steamcommunity/public/images/avatars/")
        default:
            return false
        }
    }

    private static func isAllowedArtworkURL(_ url: URL) -> Bool {
        isAllowedAvatarURL(url) || isAllowedGameArtworkURL(url)
    }

    private static func isAllowedGameArtworkURL(_ url: URL) -> Bool {
        return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            // Public assets verified on these CDNs; Cloudflare redirects to shared.steamstatic.com.
            && ["cdn.akamai.steamstatic.com", "shared.akamai.steamstatic.com", "shared.fastly.steamstatic.com", "shared.cloudflare.steamstatic.com", "shared.steamstatic.com"].contains(url.host?.lowercased() ?? "")
            && (url.path.hasPrefix("/steam/apps/") || url.path.hasPrefix("/store_item_assets/steam/apps/"))
    }

    private static func isAllowedStoreDetailsURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && url.host?.lowercased() == "store.steampowered.com" && url.path == "/api/appdetails"
    }

    private final class ArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard let url = request.url, let original = task.originalRequest?.url else {
                completionHandler(nil)
                return
            }
            let allowed: Bool
            if SteamAPI.isAllowedStoreDetailsURL(original) {
                allowed = SteamAPI.isAllowedStoreDetailsURL(url) && url.query == original.query
            } else if SteamAPI.isAllowedAvatarURL(original) {
                allowed = SteamAPI.isAllowedAvatarURL(url)
            } else {
                allowed = SteamAPI.isAllowedGameArtworkURL(original) && SteamAPI.isAllowedGameArtworkURL(url)
            }
            completionHandler(allowed ? request : nil)
        }
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
