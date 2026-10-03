import Foundation
import ImageIO

private final class ArtworkFixtures: @unchecked Sendable {
    struct Reply: Sendable { let status: Int; let headers: [String: String]; let data: Data }
    let lock = NSLock()
    private var replies: [String: Reply] = [:]
    private var requests: [String] = []
    func set(_ path: String, status: Int = 200, headers: [String: String] = [:], data: Data = Data()) {
        lock.withLock { replies[path] = Reply(status: status, headers: headers, data: data) }
    }
    func take(_ request: URLRequest) -> Reply {
        lock.withLock {
            requests.append(request.url!.absoluteString)
            return replies[request.url!.path] ?? Reply(status: 404, headers: [:], data: Data())
        }
    }
    var count: Int { lock.withLock { requests.count } }
}

private final class ArtworkProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = ArtworkFixtures()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.fixtures.take(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct NintendoArtworkScenarios {
    static func image(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hourcade-nintendo-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if CommandLine.arguments.contains("--live") {
            let store = NintendoArtworkStore(cacheURL: root.appending(path: "resolutions.json"))
            let ids = ["0100f2c0115b6000", "0100000000010000", "01007ef00011e000"]
            await store.cache(titleIDs: ids, artworkDirectory: root)
            for id in ids {
                let data = try Data(contentsOf: root.appending(path: "nintendo-\(id)-hero-hd.jpg"))
                precondition(NintendoArtworkParser.isWideImage(data), "Live banner invalid for \(id)")
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
                print("\(id): \(p[kCGImagePropertyPixelWidth]!)×\(p[kCGImagePropertyPixelHeight]!) official banner cached")
            }
            print("3 live HK eShop download scenarios passed")
            return
        }
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let parse = NintendoArtworkParser.self
        expect(parse.normalizedTitleID("0400F2C0115B6000") == "0400f2c0115b6000", "Switch 2 uppercase ID")
        for id in ["../etc/passwd", "0100f2c0115b600", "0100f2c0115b60000", " 0100f2c0115b6000", "0100g2c0115b6000"] {
            expect(parse.normalizedTitleID(id) == nil, "Reject invalid title ID")
        }
        let location = "/HK/zh/titles/70010000063717"
        expect(parse.titlePage(location: location, country: "HK") != nil, "Relative product redirect")
        expect(parse.titlePage(location: "https://ec.nintendo.com" + location, country: "HK") != nil, "Absolute product redirect")
        for location in ["https://evil.test/HK/zh/titles/70010000063717", "/US/en/titles/70010000063717", "/HK/zh/titles/123", "/HK/zh/titles/70010000063717?next=foo", "https://ec.nintendo.com:444/HK/zh/titles/70010000063717", "https://www.nintendo.com.hk/software/switch/"] {
            expect(parse.titlePage(location: location, country: "HK") == nil, "Reject non-product redirect")
        }
        let banner = "https://img-eshop.cdn.nintendo.net/i/banner.jpg"
        for url in ["http://img-eshop.cdn.nintendo.net/i/a", "https://img-eshop.cdn.nintendo.net.evil.test/i/a", "https://name:secret@img-eshop.cdn.nintendo.net/i/a"] {
            expect(!parse.isAllowedBanner(URL(string: url)!), "Reject unsafe artwork URL")
        }
        let html = "<script type='application/ld+json'>{\"@graph\":[{\"@type\":\"Organization\",\"image\":\"https://evil.test/i/a\"},{\"@type\":[\"Thing\",\"VideoGame\"],\"image\":{\"url\":\"\(banner)\"}}]}</script>"
        expect(parse.bannerURL(html: html)?.absoluteString == banner, "Graph and ImageObject parsing")
        expect(parse.bannerURL(html: "<script type=\"application/ld+json\">{bad json}</script>") == nil, "Malformed JSON-LD")
        expect(parse.bannerURL(html: "<img src='\(banner)'>") == nil, "Do not match recommendations")
        let wide = image(width: 1920, height: 1080)
        expect(parse.isWideImage(wide), "Native wide banner")
        expect(!parse.isWideImage(image(width: 1024, height: 1024)), "Reject square as hero-hd")
        expect(!parse.isWideImage(Data("<html>error</html>".utf8)), "Reject HTML error body")
        expect(!parse.isWideImage(Data(repeating: 0, count: 8 * 1024 * 1024 + 1)), "Reject oversized data")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let fixture = ArtworkProtocol.fixtures
        let id = "0100f2c0115b6000"
        fixture.set("/apps/\(id)/HK", status: 307, headers: ["Location": "/HK/zh/titles/70010000063717"])
        fixture.set("/HK/zh/titles/70010000063717", data: Data(html.utf8))
        fixture.set("/i/banner.jpg", data: wide)
        let cache = root.appending(path: "resolutions.json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = NintendoArtworkStore(cacheURL: cache, session: session)
        await store.cache(titleIDs: [id, id.uppercased(), "invalid"], artworkDirectory: root, now: now)
        let destination = root.appending(path: "nintendo-\(id)-hero-hd.jpg")
        expect(FileManager.default.fileExists(atPath: destination.path), "Official banner uses compatible cache name")
        expect(fixture.count == 3, "Deduplicate and bound visible games")
        await store.cache(titleIDs: [id], artworkDirectory: root, now: now)
        expect(fixture.count == 3, "Existing validated image uses zero requests")
        try FileManager.default.removeItem(at: destination)
        let reloaded = NintendoArtworkStore(cacheURL: cache, session: session)
        await reloaded.cache(titleIDs: [id], artworkDirectory: root, now: now)
        expect(fixture.count == 4, "Persisted positive URL repairs deleted artwork without pages")
        try Data("corrupt".utf8).write(to: destination)
        fixture.set("/i/banner.jpg", status: 200, data: Data("<html>not image</html>".utf8))
        await reloaded.cache(titleIDs: [id], artworkDirectory: root, now: now)
        expect(try Data(contentsOf: destination) == Data("corrupt".utf8), "Invalid network image never overwrites a file")
        let count = fixture.count
        await reloaded.cache(titleIDs: [id], artworkDirectory: root, now: now.addingTimeInterval(60))
        expect(fixture.count == count, "Failed download gets short backoff")
        fixture.set("/i/banner.jpg", data: wide)
        await reloaded.cache(titleIDs: [id], artworkDirectory: root, now: now.addingTimeInterval(3_601))
        expect(parse.isWideImage(try Data(contentsOf: destination)), "Expired failure re-resolves and repairs corrupt cache")

        let absent = "0100000000000000"
        fixture.set("/apps/\(absent)/HK", status: 307, headers: ["Location": "https://www.nintendo.com.hk/software/switch/"])
        let flaky = "0100000000000001"
        fixture.set("/apps/\(flaky)/HK", status: 503)
        await store.cache(titleIDs: [absent, flaky], artworkDirectory: root, now: now)
        let beforeRetry = fixture.count
        await store.cache(titleIDs: [absent, flaky], artworkDirectory: root, now: now.addingTimeInterval(60))
        expect(fixture.count == beforeRetry, "Missing and server failure cache prevents repeated requests")
        await store.cache(titleIDs: [absent, flaky], artworkDirectory: root, now: now.addingTimeInterval(3_601))
        expect(fixture.count == beforeRetry + 1, "Transient failure retries sooner than catalog absence")
        print("\(checks) Nintendo artwork parser/cache scenarios passed")
    }
}
