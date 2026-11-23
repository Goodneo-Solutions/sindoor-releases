import CoreLocation
import Foundation

/// A place in a site: a ref (`door`, `fixture:12`), a point in millimetres on a level, or a coordinate on a level.
/// A string literal is a ref: `site.route(from: "door", to: "till")`.
public enum SindoorPlace: ExpressibleByStringLiteral, Equatable {
    case ref(String)
    case point(level: String?, x: Double, y: Double)
    case coordinate(level: String, CLLocationCoordinate2D)

    public init(stringLiteral value: String) { self = .ref(value) }

    public static func == (a: SindoorPlace, b: SindoorPlace) -> Bool {
        switch (a, b) {
        case let (.ref(x), .ref(y)): return x == y
        case let (.point(l1, x1, y1), .point(l2, x2, y2)): return l1 == l2 && x1 == x2 && y1 == y2
        case let (.coordinate(l1, c1), .coordinate(l2, c2)): return l1 == l2 && c1.latitude == c2.latitude && c1.longitude == c2.longitude
        default: return false
        }
    }
}

/// A point in millimetres on a level.
public struct SindoorPoint: Equatable, Sendable {
    public var level: String
    public var x: Double
    public var y: Double
    public init(level: String, x: Double, y: Double) { self.level = level; self.x = x; self.y = y }
}

private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

/// One step of a route: `kind` (`start`, `straight`, `left`, `right`, `slight_left`, `connector`, `arrive` …), its
/// level, where it is (mm), the distance to walk after it and the turn angle.
public struct SindoorStep: Equatable, Sendable {
    public var kind: String
    public var level: String
    public var at: [Double]
    public var distanceMm: Double
    public var angleDeg: Double?

    public init(kind: String, level: String, at: [Double] = [], distanceMm: Double = 0, angleDeg: Double? = nil) {
        self.kind = kind; self.level = level; self.at = at; self.distanceMm = distanceMm; self.angleDeg = angleDeg
    }

    init(json o: [String: Any]) {
        self.init(kind: (o["kind"] as? String) ?? "", level: (o["level"] as? String) ?? "",
                  at: (o["at"] as? [Any])?.compactMap(num) ?? [], distanceMm: num(o["distance_mm"]) ?? 0, angleDeg: num(o["angle_deg"]))
    }
}

/// One level's part of a route: its polyline in millimetres (`[x, y]` pairs).
public struct SindoorLeg: Equatable, Sendable {
    public var level: String
    public var polyline: [[Double]]
    public init(level: String, polyline: [[Double]]) { self.level = level; self.polyline = polyline }
}

/// A walking route as the engine answers it (`length_mm`, `duration_s`, `legs`, `steps`, `connectors`, `version`);
/// `json` keeps the whole answer.
public struct SindoorRoute {
    public var lengthMm: Double
    public var durationS: Double
    public var level: String
    public var legs: [SindoorLeg]
    public var steps: [SindoorStep]
    public var json: [String: Any]

    public init(json o: [String: Any]) {
        lengthMm = num(o["length_mm"]) ?? 0
        durationS = num(o["duration_s"]) ?? 0
        level = (o["level"] as? String) ?? ""
        legs = ((o["legs"] as? [[String: Any]]) ?? []).map { l in
            SindoorLeg(level: (l["level"] as? String) ?? "",
                       polyline: ((l["polyline"] as? [Any]) ?? []).map { (($0 as? [Any]) ?? []).compactMap(num) })
        }
        steps = ((o["steps"] as? [[String: Any]]) ?? []).map(SindoorStep.init(json:))
        json = o
    }

    public init(lengthMm: Double = 0, durationS: Double = 0, level: String = "", legs: [SindoorLeg] = [], steps: [SindoorStep] = []) {
        self.lengthMm = lengthMm; self.durationS = durationS; self.level = level; self.legs = legs; self.steps = steps; self.json = [:]
    }
}

/// Where the device is: the filter's estimate (mm on a level, accuracy in mm, `at` its time in ms) with its
/// coordinate through the level's anchor; `json` keeps the whole answer.
public struct SindoorEstimate {
    public var x: Double
    public var y: Double
    public var level: String
    public var accMm: Double
    public var at: Double
    public var coordinate: CLLocationCoordinate2D
    public var json: [String: Any]

    public init(x: Double, y: Double, level: String, accMm: Double, at: Double = 0, coordinate: CLLocationCoordinate2D, json: [String: Any] = [:]) {
        self.x = x; self.y = y; self.level = level; self.accMm = accMm; self.at = at; self.coordinate = coordinate; self.json = json
    }

    public var point: SindoorPoint { SindoorPoint(level: level, x: x, y: y) }
}

/// What a device downloads for a site (`GET /v1/indoor/sites/{site}/package`): `{site, package, overlay: {revision,
/// overlay}, live}`. Keep `data` (or `json`) in a cache and pass it back to `SindoorSite.fromDownload` offline.
public struct SindoorDownload {
    public var json: [String: Any]
    public init(json: [String: Any]) { self.json = json }
    public var site: String? { json["site"] as? String }
    /// The download as JSON bytes, for a file cache.
    public var data: Data { (try? JSONSerialization.data(withJSONObject: json)) ?? Data() }
}

/// A token for the full form of a site (`POST /v1/indoor/token`, server side).
public struct SindoorToken: Equatable, Sendable {
    public var token: String
    public var expiresAt: Double
    public init(token: String, expiresAt: Double) { self.token = token; self.expiresAt = expiresAt }
}
