import CoreLocation
import Foundation

/// A level's geo anchor: where its origin (0, 0) lies, the plan's rotation (degrees clockwise) and its scale.
public struct SindoorAnchor: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var rotationDeg: Double
    public var scale: Double

    public init(lat: Double, lon: Double, rotationDeg: Double = 0, scale: Double = 1) {
        self.lat = lat
        self.lon = lon
        self.rotationDeg = rotationDeg
        self.scale = scale
    }

    /// From the layer's `anchor` object (`{lat, lon, rotation_deg?, scale?}`); none → 0° / 0° (a local frame).
    public init(json: [String: Any]?) {
        let n = { (k: String) -> Double? in (json?[k] as? NSNumber)?.doubleValue }
        self.init(lat: n("lat") ?? 0, lon: n("lon") ?? 0, rotationDeg: n("rotation_deg") ?? 0, scale: n("scale") ?? 1)
    }
}

/// Level millimetres ⇄ latitude / longitude through a level's anchor: the formulas of sIndoor's
/// sindoor_model::outdoor (`level_to_geo` / `geo_to_level`), the same as the Web SDK's geo.js and sMap's indoor layer.
public enum SindoorGeo {
    /// Millimetres per degree of latitude and of longitude at a latitude.
    public static func mmPerDegree(_ lat: Double) -> (lat: Double, lon: Double) {
        let r = lat * .pi / 180
        let latM = 111132.92 - 559.82 * cos(2 * r) + 1.175 * cos(4 * r)
        let lonM = 111412.84 * cos(r) - 93.5 * cos(3 * r)
        return (latM * 1000, lonM * 1000)
    }

    /// A level point (mm, x east, y south) → its coordinate.
    public static func levelToCoordinate(_ a: SindoorAnchor, x: Double, y: Double) -> CLLocationCoordinate2D {
        let k = mmPerDegree(a.lat)
        let rot = a.rotationDeg * .pi / 180
        let s = sin(rot), c = cos(rot)
        let xs = x * a.scale, ys = y * a.scale
        let e = xs * c - ys * s, south = xs * s + ys * c
        return CLLocationCoordinate2D(latitude: a.lat - south / k.lat, longitude: a.lon + e / k.lon)
    }

    /// A coordinate → a level point (mm).
    public static func coordinateToLevel(_ a: SindoorAnchor, _ p: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let k = mmPerDegree(a.lat)
        let e = (p.longitude - a.lon) * k.lon, south = -(p.latitude - a.lat) * k.lat
        let rot = a.rotationDeg * .pi / 180
        let s = sin(rot), c = cos(rot)
        return ((e * c + south * s) / a.scale, (-e * s + south * c) / a.scale)
    }
}
