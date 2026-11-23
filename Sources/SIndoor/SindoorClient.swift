import Foundation

/// The Open Platform's indoor routes (sIndoor DESIGN.md Part 2h, "P6 interfaces"): a site's package for the device,
/// its layer, public sites, and a token for the full form (server side). The Web SDK's `SindoorClient` in Swift.
///
/// Credentials:
/// - `key`: an sMap map key (`smk_…`) — the customer form of the account's own and public sites; sent as the
///   `X-SMap-Key` header and `?key=`.
/// - `token`: an sIndoor token (`si1.…`) the developer's server got from `POST /v1/indoor/token` — the full form;
///   sent as `Authorization: Bearer`, never in the URL.
/// - `apiKey`: an Open Platform server key — only on a server, never in an app (Bearer).
public final class SindoorClient {
    public static let defaultBaseURL = URL(string: "https://open.superroute.ca/v1/indoor")!

    public enum Form: String, Sendable {
        case customer
        case full
    }

    public let key: String?
    public let token: String?
    public let apiKey: String?
    public let baseURL: URL
    let session: URLSession

    public init(key: String? = nil, token: String? = nil, apiKey: String? = nil, baseURL: URL = SindoorClient.defaultBaseURL,
                session: URLSession = .shared) {
        self.key = key
        self.token = token
        self.apiKey = apiKey
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        self.baseURL = URL(string: s) ?? baseURL
        self.session = session
    }

    /// The headers of every request.
    public func headers() -> [String: String] {
        var h = ["Accept": "application/json"]
        if let bearer = token ?? apiKey { h["Authorization"] = "Bearer \(bearer)" }
        if let key { h["X-SMap-Key"] = key }
        return h
    }

    /// A route's URL: the base, the path, `?key=` for a map key without a token, then the query.
    public func url(_ path: String, query: [(String, String?)] = []) -> URL {
        var c = URLComponents(string: baseURL.absoluteString + path)!
        var items: [URLQueryItem] = []
        if let key, token == nil { items.append(URLQueryItem(name: "key", value: key)) }
        for (k, v) in query { if let v { items.append(URLQueryItem(name: k, value: v)) } }
        if !items.isEmpty { c.queryItems = items }
        return c.url!
    }

    static func segment(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// One request; a non-2xx answer becomes a `SindoorError` with the platform's code (else `http_<status>`).
    public func request(_ method: String, _ path: String, query: [(String, String?)] = [], body: [String: Any]? = nil) async throws -> Any {
        var r = URLRequest(url: url(path, query: query))
        r.httpMethod = method
        for (k, v) in headers() { r.setValue(v, forHTTPHeaderField: k) }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: r)
        } catch {
            throw SindoorError("network", error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let v = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard (200..<300).contains(status) else {
            let e = (v as? [String: Any])?["error"] as? [String: Any]
            throw SindoorError((e?["code"] as? String) ?? "http_\(status)", (e?["message"] as? String) ?? "HTTP \(status)",
                               refs: (e?["refs"] as? [Any])?.map { "\($0)" } ?? [])
        }
        guard let v else { throw SindoorError("bad_answer", "the answer is not JSON") }
        return v
    }

    /// `{site, package, overlay: {revision, overlay}, live}` — the form the credentials allow (customer by default).
    public func package(site: String, form: Form = .customer) async throws -> SindoorDownload {
        guard let o = try await request("GET", "/sites/\(Self.segment(site))/package", query: [("form", form.rawValue)]) as? [String: Any] else {
            throw SindoorError("bad_answer", "expected a site download")
        }
        return SindoorDownload(json: o)
    }

    /// The layer GeoJSON of a site (what sMap's indoor layer draws), without downloading the package.
    public func layer(site: String) async throws -> [String: Any] {
        guard let o = try await request("GET", "/sites/\(Self.segment(site))/layer") as? [String: Any] else {
            throw SindoorError("bad_answer", "expected the layer GeoJSON")
        }
        return o
    }

    /// Public sites in a bounding box `[west, south, east, north]` → `[{site, name, bbox, levels}]`.
    public func publicSites(bbox: [Double]) async throws -> [[String: Any]] {
        let b = bbox.map { Self.number($0) }.joined(separator: ",")
        guard let l = try await request("GET", "/public-sites", query: [("bbox", b)]) as? [[String: Any]] else {
            throw SindoorError("bad_answer", "expected a list of sites")
        }
        return l
    }

    /// Server side only (an Open Platform key): a short-lived token for a site's full form.
    public func issueToken(site: String, form: Form = .full, subject: String? = nil, ttlS: Int? = nil) async throws -> SindoorToken {
        var body: [String: Any] = ["site": site, "form": form.rawValue]
        if let subject { body["subject"] = subject }
        if let ttlS { body["ttl_s"] = ttlS }
        guard let o = try await request("POST", "/token", body: body) as? [String: Any], let t = o["token"] as? String else {
            throw SindoorError("bad_answer", "expected {token, expires_at}")
        }
        return SindoorToken(token: t, expiresAt: (o["expires_at"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// A number as JavaScript prints it (`-79.4`, `43`), for the bbox.
    static func number(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }
}
