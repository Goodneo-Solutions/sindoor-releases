import Foundation

/// A beacon heard: its engine id, RSSI (dBm) and power at 1 m when known.
public struct SindoorBeaconReading: Equatable, Sendable {
    public var id: String
    public var rssi: Double
    public var tx: Double?
    public init(id: String, rssi: Double, tx: Double? = nil) { self.id = id; self.rssi = rssi; self.tx = tx }
    public var json: [String: Any] {
        var o: [String: Any] = ["id": id, "rssi": rssi]
        if let tx { o["tx"] = tx }
        return o
    }
}

/// The beacon ids the engine uses (sindoor-model `Beacon`, IQ12): `ib:<uuid>:<major>:<minor>` (the UUID in lower case
/// with its hyphens, major and minor in decimal) and `ed:<namespace>:<instance>` (Eddystone-UID, lower-case hex).
public enum SindoorBeaconID {
    public static func iBeacon(uuid: String, major: Int, minor: Int) -> String {
        "ib:\(uuid.trimmingCharacters(in: .whitespaces).lowercased()):\(major):\(minor)"
    }

    public static func eddystone(namespace: String, instance: String) -> String {
        "ed:\(namespace.lowercased()):\(instance.lowercased())"
    }

    private static let uuidPattern = try! NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

    /// The distinct proximity UUIDs (lower case, sorted) of the iBeacons among beacon rows (`site.beacons()`) or ids;
    /// Eddystone ids and ids without a valid UUID are left out.
    public static func iBeaconUUIDs(_ beacons: [Any]) -> [String] {
        var out = Set<String>()
        for b in beacons {
            let raw = (b as? [String: Any]).map { "\($0["id"] ?? "")" } ?? "\(b)"
            let id = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard id.hasPrefix("ib:") else { continue }
            let parts = id.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let u = String(parts[1])
            if uuidPattern.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)) != nil { out.insert(u) }
        }
        return out.sorted()
    }

    /// An Eddystone service data frame (service 0xFEAA) → the UID frame's id and its power at 1 m (the frame's power
    /// at 0 m less 41 dB); nil for other frames (URL, TLM, EID) or short data.
    public static func eddystoneUID(serviceData d: Data) -> (id: String, tx: Double)? {
        let b = [UInt8](d)
        guard b.count >= 18, b[0] == 0x00 else { return nil }
        let hex = { (s: ArraySlice<UInt8>) in s.map { String(format: "%02x", $0) }.joined() }
        let tx0 = Double(Int8(bitPattern: b[1]))
        return (eddystone(namespace: hex(b[2..<12]), instance: hex(b[12..<18])), tx0 - 41)
    }

    /// Readings of one round → one per id (the strongest); unknown signals (RSSI 0, CoreLocation's "not measured")
    /// are left out.
    public static func merge(_ readings: [SindoorBeaconReading]) -> [SindoorBeaconReading] {
        var best: [String: SindoorBeaconReading] = [:]
        for r in readings where r.rssi != 0 {
            if let b = best[r.id], b.rssi >= r.rssi { continue }
            best[r.id] = r
        }
        return best.values.sorted { $0.id < $1.id }
    }
}
