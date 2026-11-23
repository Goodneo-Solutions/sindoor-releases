import Foundation
import SindoorFFI

/// The C library (crates/sindoor-ffi, include/sindoor.h): JSON in, JSON out, returned strings freed here. Every entry
/// point of the header is called from this file, so the linker keeps them all without `-u` flags.
enum SindoorNative {
    /// A returned C string → a Swift string, the C string freed.
    static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { sindoor_string_free(p) }
        return String(cString: p)
    }

    static func lastError() -> String {
        take(sindoor_last_error()) ?? "unknown error"
    }

    static func version() -> String {
        take(sindoor_version()) ?? ""
    }

    static func json(_ v: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(v) else { throw SindoorError("bad_request", "not a JSON object or list") }
        let d = try JSONSerialization.data(withJSONObject: v, options: [])
        return String(decoding: d, as: UTF8.self)
    }

    /// An engine answer: parsed, `{error}` thrown as a SindoorError; no answer at all → the last error.
    static func parse(_ answer: String?) throws -> Any {
        guard let s = answer else { throw SindoorError("engine_error", lastError()) }
        let v: Any
        do {
            v = try JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])
        } catch {
            throw SindoorError("engine_error", "the engine answered no JSON")
        }
        if let e = SindoorError.from(answer: v) { throw e }
        return v
    }

    static func object(_ answer: String?) throws -> [String: Any] {
        let v = try parse(answer)
        guard let o = v as? [String: Any] else { throw SindoorError("engine_error", "expected a JSON object") }
        return o
    }

    // The handles, as opaque pointers.
    typealias Site = OpaquePointer
    typealias Locator = OpaquePointer

    static func siteFromPackage(_ pkg: String, _ overlay: String, _ live: String, _ revision: UInt64) -> Site? {
        sindoor_site_from_package(pkg, overlay, live, revision)
    }

    static func siteFromRows(_ rows: String, _ overlay: String, _ live: String, _ revision: UInt64) -> Site? {
        sindoor_site_new(rows, overlay, live, revision)
    }

    static func free(site: Site) { sindoor_site_free(site) }
    static func route(_ s: Site, _ req: String) -> String? { take(sindoor_route(s, req)) }
    static func approach(_ s: Site, _ req: String) -> String? { take(sindoor_approach(s, req)) }
    static func tour(_ s: Site, _ req: String) -> String? { take(sindoor_tour(s, req)) }
    static func levels(_ s: Site) -> String? { take(sindoor_levels(s)) }
    static func layer(_ s: Site) -> String? { take(sindoor_layer(s)) }
    static func vehicleRoute(_ s: Site, _ req: String) -> String? { take(sindoor_vehicle_route(s, req)) }
    static func vehicles(_ s: Site) -> String? { take(sindoor_vehicles(s)) }

    static func locator(_ s: Site, _ config: String) -> Locator? { sindoor_locator_new(s, config) }
    static func observe(_ l: Locator, _ obs: String) -> String? { take(sindoor_locator_observe(l, obs)) }
    static func state(_ l: Locator) -> String? { take(sindoor_locator_state(l)) }
    static func setCalibration(_ l: Locator, _ cal: String) -> String? { take(sindoor_locator_set_calibration(l, cal)) }
    static func free(locator: Locator) { sindoor_locator_free(locator) }
}
