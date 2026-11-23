import CoreLocation
import Foundation

/// A positioning filter running on the device (steps, heading, pressure, beacons, scans, GPS → estimates). Nothing is
/// sent anywhere. `SindoorSensors` and `SindoorBeacons` feed it on an iPhone; any source may call `observe`.
public final class SindoorLocator {
    public let site: SindoorSite
    private let lock = NSLock()
    private var inner: SindoorNative.Locator?
    /// The latest estimate.
    public private(set) var last: SindoorEstimate?

    init(site: SindoorSite, config: [String: Any]) throws {
        self.site = site
        let cfg = try SindoorNative.json(config)
        let l = try site.call { SindoorNative.locator($0, cfg) }
        guard let l else { throw SindoorError("invalid_config", SindoorNative.lastError()) }
        inner = l
    }

    deinit {
        if let l = inner { SindoorNative.free(locator: l) }
    }

    private func call<T>(_ body: (SindoorNative.Locator) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let l = inner else { throw SindoorError("disposed", "the locator was disposed") }
        return try body(l)
    }

    /// One observation (`{t, kind, …}` as the engine takes them; `SindoorObservation` builds them) → the estimate with
    /// its coordinate, or nil before the first fix.
    @discardableResult
    public func observe(_ observation: [String: Any]) throws -> SindoorEstimate? {
        try observeAny(observation)
    }

    /// Several observations at once.
    @discardableResult
    public func observe(_ observations: [[String: Any]]) throws -> SindoorEstimate? {
        try observeAny(observations)
    }

    private func observeAny(_ obs: Any) throws -> SindoorEstimate? {
        let body = try SindoorNative.json(obs)
        let v = try call { try SindoorNative.parse(SindoorNative.observe($0, body)) }
        guard let o = v as? [String: Any], let level = o["level"] as? String,
              let x = (o["x"] as? NSNumber)?.doubleValue, let y = (o["y"] as? NSNumber)?.doubleValue else { return nil }
        let c = (try? site.toCoordinate(level: level, x: x, y: y)) ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var j = o
        j["lng"] = c.longitude
        j["lat"] = c.latitude
        let e = SindoorEstimate(x: x, y: y, level: level, accMm: (o["acc_mm"] as? NSNumber)?.doubleValue ?? 0,
                                at: (o["at"] as? NSNumber)?.doubleValue ?? 0, coordinate: c, json: j)
        lock.lock()
        last = e
        lock.unlock()
        return e
    }

    /// `{step_scale, features}` — keep `step_scale` per person on the device and pass it back in the config.
    public func state() throws -> [String: Any] {
        try call { try SindoorNative.object(SindoorNative.state($0)) }
    }

    /// A site's calibration (`GET /calibration` body).
    @discardableResult
    public func setCalibration(_ calibration: [String: Any]) throws -> Any {
        let body = try SindoorNative.json(calibration)
        return try call { try SindoorNative.parse(SindoorNative.setCalibration($0, body)) }
    }

    public func dispose() {
        lock.lock()
        defer { lock.unlock() }
        if let l = inner { SindoorNative.free(locator: l) }
        inner = nil
    }
}

/// Observations as the engine takes them (`t` in ms since 1970). Headings are compass bearings (`frame: north`, 0 =
/// north, clockwise), turned onto the plan by the level's anchor.
public enum SindoorObservation {
    public static func ms(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }

    /// `n` steps towards `headingDeg`.
    public static func steps(_ n: Int, headingDeg: Double, stepMm: Double? = nil, frame: String = "north", at: Date = Date()) -> [String: Any] {
        var o: [String: Any] = ["t": ms(at), "kind": "steps", "n": n, "heading_deg": headingDeg, "frame": frame]
        if let stepMm { o["step_mm"] = stepMm }
        return o
    }

    /// The current heading.
    public static func heading(_ deg: Double, source: String = "fused", frame: String = "north", at: Date = Date()) -> [String: Any] {
        ["t": ms(at), "kind": "heading", "deg": deg, "source": source, "frame": frame]
    }

    /// Barometric pressure, hPa.
    public static func pressure(_ hpa: Double, at: Date = Date()) -> [String: Any] {
        ["t": ms(at), "kind": "pressure", "hpa": hpa]
    }

    /// Beacons heard in one round.
    public static func ble(_ beacons: [SindoorBeaconReading], at: Date = Date()) -> [String: Any] {
        ["t": ms(at), "kind": "ble", "beacons": beacons.map(\.json)]
    }

    /// A position code, location or fixture scanned: the device stands at it.
    public static func scan(_ ref: String, sigmaMm: Double? = nil, at: Date = Date()) -> [String: Any] {
        var o: [String: Any] = ["t": ms(at), "kind": "scan", "ref": ref]
        if let sigmaMm { o["sigma_mm"] = sigmaMm }
        return o
    }

    /// The user placed themselves at a point.
    public static func place(_ p: SindoorPoint, sigmaMm: Double = 500, at: Date = Date()) -> [String: Any] {
        ["t": ms(at), "kind": "place", "level": p.level, "x": p.x, "y": p.y, "sigma_mm": sigmaMm]
    }

    /// A satellite fix (used on sites with an outdoor level).
    public static func gps(_ c: CLLocationCoordinate2D, accuracyM: Double, altitudeM: Double? = nil, at: Date = Date()) -> [String: Any] {
        var o: [String: Any] = ["t": ms(at), "kind": "gps", "lat": c.latitude, "lon": c.longitude, "acc_m": accuracyM]
        if let altitudeM { o["alt_m"] = altitudeM }
        return o
    }
}
