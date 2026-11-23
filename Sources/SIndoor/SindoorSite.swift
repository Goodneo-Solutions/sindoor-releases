import CoreLocation
import Foundation

/// A site on the device: downloaded once (or from a cache), compiled by the engine, routed and positioned offline.
/// The Web SDK's `SindoorSite` in Swift. Safe to use from any thread (calls are serialised).
public final class SindoorSite {
    let handle: NSLock = NSLock()
    private var inner: SindoorNative.Site?
    private var cachedLayer: [String: Any]?
    private var cachedLevels: [String: Any]?

    /// What was downloaded (`{site, package, overlay, live}`), for a cache: `SindoorSite.fromDownload(site.download)`.
    public let download: SindoorDownload

    private init(inner: SindoorNative.Site, download: SindoorDownload) {
        self.inner = inner
        self.download = download
    }

    deinit {
        if let s = inner { SindoorNative.free(site: s) }
    }

    /// The engine's version (`sindoor_version`).
    public static var engineVersion: String { SindoorNative.version() }

    // MARK: - Making a site

    /// Download a site's package through a `SindoorClient` and compile it here.
    public static func load(site: String, client: SindoorClient, form: SindoorClient.Form = .customer) async throws -> SindoorSite {
        try fromDownload(try await client.package(site: site, form: form))
    }

    /// A site from a download kept earlier (offline).
    public static func fromDownload(_ d: SindoorDownload) throws -> SindoorSite {
        try fromDownload(d.json)
    }

    /// A site from a download's JSON bytes (a file cache).
    public static func fromDownload(_ data: Data) throws -> SindoorSite {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SindoorError("bad_download", "expected {package, overlay, live}")
        }
        return try fromDownload(o)
    }

    /// A site from a download's JSON object `{site, package, overlay: {revision, overlay}, live}`.
    public static func fromDownload(_ d: [String: Any]) throws -> SindoorSite {
        guard let pkg = d["package"], pkg is [String: Any] else { throw SindoorError("bad_download", "expected {package, overlay, live}") }
        let ovWrap = d["overlay"] as? [String: Any]
        let ov: Any = ovWrap?["overlay"] ?? ovWrap ?? [String: Any]()
        let rev = (ovWrap?["revision"] as? NSNumber)?.uint64Value ?? 0
        let live = d["live"] ?? [Any]()
        let s = try SindoorNative.siteFromPackage(SindoorNative.json(pkg), SindoorNative.json(ov), SindoorNative.json(live), rev)
        guard let s else { throw SindoorError("invalid_site", SindoorNative.lastError()) }
        return SindoorSite(inner: s, download: SindoorDownload(json: d))
    }

    /// A site package with no overlay (e.g. a file the developer ships with the app).
    public static func fromPackage(_ package: [String: Any], overlay: [String: Any] = [:], live: [Any] = [], revision: UInt64 = 0) throws -> SindoorSite {
        try fromDownload(["package": package, "overlay": ["revision": revision, "overlay": overlay] as [String: Any], "live": live])
    }

    /// A site package from its JSON bytes.
    public static func fromPackage(_ data: Data) throws -> SindoorSite {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw SindoorError("invalid_site", "the package is not a JSON object") }
        return try fromPackage(o)
    }

    /// A site from Superroute's floor plan rows (as `GET /v1/sites/{id}/rows` in sIndoor; the handheld's form).
    public static func fromRows(_ rows: [String: Any], overlay: [String: Any] = [:], live: [Any] = [], revision: UInt64 = 0) throws -> SindoorSite {
        let s = try SindoorNative.siteFromRows(SindoorNative.json(rows), SindoorNative.json(overlay), SindoorNative.json(live), revision)
        guard let s else { throw SindoorError("invalid_site", SindoorNative.lastError()) }
        return SindoorSite(inner: s, download: SindoorDownload(json: ["rows": rows]))
    }

    // MARK: - Reading

    func call<T>(_ body: (SindoorNative.Site) throws -> T) throws -> T {
        handle.lock()
        defer { handle.unlock() }
        guard let s = inner else { throw SindoorError("disposed", "the site was disposed") }
        return try body(s)
    }

    /// The site's id (the download's `site`, else the package's `site.id`).
    public var id: String? {
        download.site ?? ((download.json["package"] as? [String: Any])?["site"] as? [String: Any])?["id"] as? String
    }

    /// The compiled site's version (the layer's `version`).
    public var version: String {
        ((try? layer())?["version"] as? String) ?? ""
    }

    /// Walk from → to; each end a ref, a point in millimetres or a coordinate on a level. `role` `customer`, `staff`,
    /// `delivery` or `all`; `profile` a movement profile (default the site's pedestrian); `at` the time the walk happens
    /// (opening hours, closures; default now), sent to the engine in Unix seconds.
    public func route(from: SindoorPlace, to: SindoorPlace, role: String? = nil, profile: String? = nil, at: Date? = nil,
                      options: [String: Any] = [:]) throws -> SindoorRoute {
        var req = options
        req["from"] = try toEngine(from)
        req["to"] = try toEngine(to)
        if let role { req["role"] = role }
        if let profile { req["profile"] = profile }
        if let at { req["at"] = Int(at.timeIntervalSince1970) }
        let body = try SindoorNative.json(req)
        return SindoorRoute(json: try call { try SindoorNative.object(SindoorNative.route($0, body)) })
    }

    /// A list of targets in the shortest order (IV13): `{targets, start?, end?}`.
    public func tour(_ request: [String: Any]) throws -> [String: Any] {
        let body = try SindoorNative.json(request)
        return try call { try SindoorNative.object(SindoorNative.tour($0, body)) }
    }

    /// From a parking point / delivery point (IV5): `{kind?, role?, profile?, vehicle_class?, at?, portal?, routes?}`.
    public func approach(_ request: [String: Any] = [:]) throws -> [String: Any] {
        let body = try SindoorNative.json(request)
        return try call { try SindoorNative.object(SindoorNative.approach($0, body)) }
    }

    /// A vehicle's route (forklift / AMR profiles, IR1).
    public func vehicleRoute(_ request: [String: Any]) throws -> [String: Any] {
        let body = try SindoorNative.json(request)
        return try call { try SindoorNative.object(SindoorNative.vehicleRoute($0, body)) }
    }

    /// The site's vehicle classes.
    public func vehicles() throws -> [String: Any] {
        try call { try SindoorNative.object(SindoorNative.vehicles($0)) }
    }

    private func levelsAnswer() throws -> [String: Any] {
        if let l = cachedLevels { return l }
        let l = try call { try SindoorNative.object(SindoorNative.levels($0)) }
        cachedLevels = l
        return l
    }

    /// The levels `[{id, ordinal, …}]`.
    public func levels() throws -> [[String: Any]] {
        (try levelsAnswer()["levels"] as? [[String: Any]]) ?? []
    }

    /// The placed beacons `[{id, level, at, …}]`; ask for Bluetooth only when this is not empty (IV14).
    public func beacons() throws -> [[String: Any]] {
        (try levelsAnswer()["beacons"] as? [[String: Any]]) ?? []
    }

    /// The indoor layer's GeoJSON — what sMap's `addIndoor` draws (`{type, frame, site, version, levels, features}`).
    public func layer() throws -> [String: Any] {
        if let l = cachedLayer { return l }
        let l = try call { try SindoorNative.object(SindoorNative.layer($0)) }
        cachedLayer = l
        return l
    }

    /// A level's anchor, from the layer.
    public func anchor(level: String) throws -> SindoorAnchor {
        let ls = (try layer()["levels"] as? [[String: Any]]) ?? []
        guard let l = ls.first(where: { ($0["id"] as? String) == level }) else {
            throw SindoorError("unknown_level", "no level \(level)", refs: [level])
        }
        return SindoorAnchor(json: l["anchor"] as? [String: Any])
    }

    /// Level millimetres → coordinate.
    public func toCoordinate(level: String, x: Double, y: Double) throws -> CLLocationCoordinate2D {
        SindoorGeo.levelToCoordinate(try anchor(level: level), x: x, y: y)
    }

    /// A coordinate on a level → its point in millimetres (rounded, as the engine takes them).
    public func fromCoordinate(level: String, _ coordinate: CLLocationCoordinate2D) throws -> SindoorPoint {
        let p = SindoorGeo.coordinateToLevel(try anchor(level: level), coordinate)
        return SindoorPoint(level: level, x: p.x.rounded(), y: p.y.rounded())
    }

    /// A place as the engine takes it.
    public func toEngine(_ p: SindoorPlace) throws -> Any {
        switch p {
        case .ref(let r): return r
        case let .point(level, x, y):
            var o: [String: Any] = ["x": x.rounded(), "y": y.rounded()]
            if let level { o["level"] = level }
            return o
        case let .coordinate(level, c):
            let pt = try fromCoordinate(level: level, c)
            return ["level": pt.level, "x": pt.x, "y": pt.y] as [String: Any]
        }
    }

    /// A positioning filter running here (steps, heading, pressure, beacons, scans, GPS → estimates). `config` as the
    /// engine takes it (`profile`, `step_scale`, `heading_offset_deg`, calibration …).
    public func locator(config: [String: Any] = [:]) throws -> SindoorLocator {
        try SindoorLocator(site: self, config: config)
    }

    /// Frees the engine's site now (otherwise on release). Later calls throw `disposed`.
    public func dispose() {
        handle.lock()
        defer { handle.unlock() }
        if let s = inner { SindoorNative.free(site: s) }
        inner = nil
    }
}
