import Foundation
import ImageIO

/// Official eShop artwork only, resolved through the public titleId redirect.
enum NintendoArtworkParser {
    static func normalizedTitleID(_ value: String) -> String? {
        let value = value.lowercased()
        return value.count == 16 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        } ? value : nil
    }

    static func titlePage(location: String, country: String) -> URL? {
        guard let base = URL(string: "https://ec.nintendo.com/"),
              let url = URL(string: location, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host == "ec.nintendo.com",
              url.port == nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/")
        let language = country == "HK" ? "zh" : "ja"
        guard parts.count == 4, parts[0] == country, parts[1] == language,
              parts[2] == "titles", parts[3].count == 14,
              parts[3].utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return url
    }

    static func isAllowedBanner(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "img-eshop.cdn.nintendo.net"
            && url.port == nil && url.user == nil && url.password == nil
            && url.path.hasPrefix("/i/")
    }

    static func bannerURL(html: String) -> URL? {
        // Read JSON-LD, not arbitrary image strings in recommendation cards.
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*\btype\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[range].utf8)),
                  let url = videoGameImage(json) else { continue }
            return url
        }
        return nil
    }

    private static func videoGameImage(_ object: Any) -> URL? {
        if let array = object as? [Any] {
            return array.lazy.compactMap(videoGameImage).first
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        let types = (dictionary["@type"] as? [String])
            ?? [dictionary["@type"] as? String].compactMap { $0 }
        if types.contains("VideoGame") {
            let images = (dictionary["image"] as? [Any])
                ?? [dictionary["image"]].compactMap { $0 }
            for image in images {
                let value = image as? String ?? (image as? [String: Any])?["url"] as? String
                if let value, let url = URL(string: value), isAllowedBanner(url) { return url }
            }
        }
        return dictionary["@graph"].flatMap(videoGameImage)
    }

    static func isWideImage(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 8 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= 1_280, height >= 400, width > height,
              width <= 8_192, height <= 8_192 else { return false }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32
        ] as CFDictionary) != nil
    }
}

/// Only the host app fetches pages. Widgets consume the existing hero-hd cache.
actor NintendoArtworkStore {
    static let shared = NintendoArtworkStore(cacheURL: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Hourcade/nintendo-artwork.json"))

    private struct Resolution: Codable {
        var bannerURL: URL?
        var retryAfter: Date
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private let cacheURL: URL
    private let session: URLSession
    private var resolutions: [String: Resolution]
    private var isSweeping = false

    init(cacheURL: URL, session: URLSession? = nil) {
        self.cacheURL = cacheURL
        resolutions = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode([String: Resolution].self, from: $0) } ?? [:]
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 25
            self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        }
    }

    func cache(titleIDs: [String], artworkDirectory: URL, now: Date = .now) async {
        guard !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false }
        var seen = Set<String>()
        let ids = titleIDs.compactMap(NintendoArtworkParser.normalizedTitleID)
            .filter { seen.insert($0).inserted }
        for id in ids {
            guard !Task.isCancelled else { return }
            let destination = artworkDirectory.appending(path: "nintendo-\(id)-hero-hd.jpg")
            if let data = try? Data(contentsOf: destination), NintendoArtworkParser.isWideImage(data) { continue }
            let country = "HK"
            let key = "\(country)-\(id)"
            if let cached = resolutions[key], cached.retryAfter > now {
                guard let banner = cached.bannerURL else { continue }
                if await download(banner, to: destination) { continue }
                // An expired CDN URL or error body must re-resolve the page
                // on the next sync, rather than poison a positive cache.
                resolutions[key] = Resolution(bannerURL: nil, retryAfter: now.addingTimeInterval(3_600))
                persist()
                continue
            }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let mapURL = URL(string: "https://ec.nintendo.com/apps/\(id)/\(country)")!
                var request = URLRequest(url: mapURL)
                request.httpMethod = "HEAD"
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 307,
                      let location = http.value(forHTTPHeaderField: "Location") else {
                    throw URLError(.badServerResponse)
                }
                guard let page = NintendoArtworkParser.titlePage(location: location, country: country) else {
                    // Only the known catalog redirect proves unavailability.
                    // Unexpected locations are temporary failures.
                    let interval: TimeInterval = location == "https://www.nintendo.com.hk/software/switch/" ? 7 * 86_400 : 3_600
                    resolutions[key] = Resolution(bannerURL: nil, retryAfter: now.addingTimeInterval(interval))
                    persist()
                    continue
                }
                let (data, pageResponse) = try await session.data(from: page)
                guard (pageResponse as? HTTPURLResponse)?.statusCode == 200,
                      data.count <= 4 * 1_024 * 1_024,
                      let html = String(data: data, encoding: .utf8),
                      let banner = NintendoArtworkParser.bannerURL(html: html) else {
                    throw URLError(.cannotParseResponse)
                }
                guard await download(banner, to: destination) else { throw URLError(.cannotDecodeContentData) }
                resolutions[key] = Resolution(bannerURL: banner, retryAfter: now.addingTimeInterval(30 * 86_400))
                persist()
            } catch {
                guard !Task.isCancelled else { return }
                resolutions[key] = Resolution(bannerURL: nil, retryAfter: now.addingTimeInterval(3_600))
                persist()
            }
        }
    }

    private func download(_ url: URL, to destination: URL) async -> Bool {
        guard NintendoArtworkParser.isAllowedBanner(url) else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  NintendoArtworkParser.isWideImage(data) else { return false }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return true
        } catch { return false }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(resolutions).write(to: cacheURL, options: .atomic)
        } catch {
            // Best effort: artwork failure never fails account synchronization.
        }
    }
}
