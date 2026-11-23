// Built where sMap's SMap module exists (iOS, or any platform with sMap from source).
#if canImport(SMap)
import Combine
import CoreLocation
import Foundation
import SIndoor
import SMap

/// The texts of the step list; any key may be replaced (translations). `metres` takes `{n}`.
public struct SindoorNavigatorText: Equatable, Sendable {
    public static let defaults: [String: String] = [
        "start": "Start",
        "arrive": "Arrive",
        "straight": "Go straight",
        "slight_left": "Bear left",
        "slight_right": "Bear right",
        "left": "Turn left",
        "right": "Turn right",
        "sharp_left": "Turn sharp left",
        "sharp_right": "Turn sharp right",
        "u_turn": "Turn around",
        "connector": "Change level",
        "level": "Level",
        "metres": "{n} m",
        "no_route": "No walking route to this place.",
    ]

    public var texts: [String: String]

    /// The defaults with `overrides` on top.
    public init(_ overrides: [String: String] = [:]) {
        texts = Self.defaults.merging(overrides) { _, new in new }
    }

    public subscript(_ key: String) -> String? { texts[key] }

    static func format(_ t: String, _ vars: [String: String]) -> String {
        var out = t
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }

    /// A step as one line: what to do, then ` · {n} m` when it has a distance.
    public func line(_ s: SindoorStep) -> String {
        let what = texts[s.kind] ?? s.kind
        guard s.distanceMm > 0 else { return what }
        let n = Int((s.distanceMm / 1000).rounded())
        return "\(what) · " + Self.format(texts["metres"] ?? "{n} m", ["n": String(n)])
    }
}

/// A route step as the step list shows it.
public struct SindoorStepLine: Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: String
    public var level: String?
    public var distanceMm: Double
    public var text: String
}

/// The navigator's options (the Web SDK's NavigatorOptions).
public struct SindoorNavigatorOptions {
    /// The indoor layer's id on the map.
    public var id: String = "sindoor"
    /// The level switcher.
    public var control: Bool = true
    /// The level shown first (default: sMap's — the level with ordinal 0, else the lowest).
    public var level: String?
    /// `customer` (default), `staff`, `delivery`, `all`.
    public var role: String = "customer"
    /// The movement profile (default the site's pedestrian).
    public var profile: String?
    /// Keep the shown level on the walker's.
    public var follow: Bool = true
    public var text: SindoorNavigatorText = SindoorNavigatorText()
    public var dot: SindoorDotStyle = SindoorDotStyle()
    public var accuracyColor: String = "#1a73e8"
    public var accuracyOpacity: Double = 0.15
    public var routeColor: String = "#1a73e8"
    public var routeWidth: Double = 5

    public init(id: String = "sindoor", control: Bool = true, level: String? = nil, role: String = "customer", profile: String? = nil,
                follow: Bool = true, text: [String: String] = [:]) {
        self.id = id
        self.control = control
        self.level = level
        self.role = role
        self.profile = profile
        self.follow = follow
        self.text = SindoorNavigatorText(text)
    }
}

/// The ready navigation screen (sIndoor DESIGN.md Part 2h, IK5) on an sMap map: the site as sMap's indoor layer with
/// its level switcher, the blue dot and its accuracy circle on the walker's level, the route line per level and the
/// step list (`steps`, shown by `SindoorStepsView`). The Web SDK's `SindoorNavigator` in Swift.
@MainActor
public final class SindoorNavigator: ObservableObject {
    public let map: SindoorMapSurface
    public let site: SindoorSite
    public let options: SindoorNavigatorOptions

    /// Where the walker is (the last estimate shown).
    @Published public private(set) var position: SindoorEstimate?
    /// The route shown.
    @Published public private(set) var route: SindoorRoute?
    /// The step list's lines (empty without a route; one `no_route` line after a failed `navigateTo`).
    @Published public private(set) var lines: [SindoorStepLine] = []

    /// Done once the map has the site (sMap's `addIndoor` waits for its data); `create` waits for it.
    public private(set) var ready: Task<Void, Error>!
    private var routeLayers: [String] = []
    private var listener: Int?

    /// Starts drawing the site on `map`; `ready` finishes once it is drawn.
    public init(map: SindoorMapSurface, site: SindoorSite, options: SindoorNavigatorOptions = SindoorNavigatorOptions()) throws {
        self.map = map
        self.site = site
        self.options = options
        let layer = try site.layer()
        let o = options
        ready = Task { @MainActor [map] in
            try await map.sindoorAddIndoor(o.id, geojson: layer, level: o.level, control: o.control)
        }
        listener = map.onIndoorLevelChange { [weak self] e in
            guard let self, e.id == self.options.id else { return }
            self.redrawDot()
        }
    }

    /// A navigator once the map has drawn the site.
    public static func create(map: SindoorMapSurface, site: SindoorSite, options: SindoorNavigatorOptions = SindoorNavigatorOptions()) async throws -> SindoorNavigator {
        let n = try SindoorNavigator(map: map, site: site, options: options)
        try await n.ready.value
        return n
    }

    // MARK: layer ids

    public var dotLayerId: String { "\(options.id)-me" }
    public var accuracyLayerId: String { "\(options.id)-me-acc" }
    public func routeLayerId(_ leg: Int) -> String { "\(options.id)-route-\(leg)" }

    /// The level shown.
    public var level: String? { try? map.indoorLevel(options.id) }

    public func setLevel(_ level: String) throws {
        try map.setIndoorLevel(options.id, level)
    }

    // MARK: position

    /// Show where the walker is (an estimate of a `SindoorLocator`); nil hides the dot.
    public func showPosition(_ e: SindoorEstimate?) {
        position = e
        if let e, options.follow, e.level != level { try? setLevel(e.level) }
        redrawDot()
    }

    private func redrawDot() {
        map.removeLayer(dotLayerId)
        map.removeLayer(accuracyLayerId)
        guard let e = position, let c = try? site.toCoordinate(level: e.level, x: e.x, y: e.y) else { return }
        let indoor = SMapIndoorRef(id: options.id, level: e.level)
        if e.accMm > 0 {
            try? map.sindoorAddCircle(accuracyLayerId, center: c, radiusM: e.accMm / 1000, color: options.accuracyColor, opacity: options.accuracyOpacity, indoor: indoor)
        }
        try? map.sindoorAddDot(dotLayerId, at: c, style: options.dot, indoor: indoor)
    }

    // MARK: route

    /// Walk to a target from the shown position (or `from`); draws the route and fills the step list. Throws
    /// `no_position` without either, and the engine's error (`unknown_point`, no route …) after showing `no_route`.
    @discardableResult
    public func navigateTo(_ target: SindoorPlace, from: SindoorPlace? = nil) throws -> SindoorRoute {
        let start: SindoorPlace
        if let from { start = from } else if let p = position { start = .point(level: p.level, x: p.x, y: p.y) } else {
            throw SindoorError("no_position", "no position yet: pass from or call showPosition first")
        }
        let r: SindoorRoute
        do {
            r = try site.route(from: start, to: target, role: options.role, profile: options.profile)
        } catch {
            clearRoute()
            lines = [SindoorStepLine(id: 0, kind: "no_route", level: nil, distanceMm: 0, text: options.text["no_route"] ?? "")]
            throw error
        }
        showRoute(r)
        return r
    }

    /// The route's lines per level, as coordinates (what `showRoute` draws).
    public func routeLines(_ r: SindoorRoute) -> [(level: String, coordinates: [CLLocationCoordinate2D])] {
        r.legs.map { leg in
            (leg.level, leg.polyline.compactMap { p -> CLLocationCoordinate2D? in
                guard p.count >= 2 else { return nil }
                return try? site.toCoordinate(level: leg.level, x: p[0], y: p[1])
            })
        }
    }

    /// Draw an engine route (one line per leg, each tied to its level) and its steps.
    public func showRoute(_ r: SindoorRoute) {
        clearRoute()
        route = r
        for (i, l) in routeLines(r).enumerated() {
            let id = routeLayerId(i)
            try? map.sindoorAddLine(id, coordinates: l.coordinates, color: options.routeColor, width: options.routeWidth,
                                    indoor: SMapIndoorRef(id: options.id, level: l.level))
            routeLayers.append(id)
        }
        lines = steps(r)
    }

    /// The route's steps as text lines (also what the step list shows).
    public func steps(_ r: SindoorRoute? = nil) -> [SindoorStepLine] {
        guard let r = r ?? route else { return [] }
        return r.steps.enumerated().map { i, s in
            SindoorStepLine(id: i, kind: s.kind, level: s.level.isEmpty ? nil : s.level, distanceMm: s.distanceMm, text: options.text.line(s))
        }
    }

    public func clearRoute() {
        for id in routeLayers { map.removeLayer(id) }
        routeLayers = []
        route = nil
        lines = []
    }

    /// Removes everything the navigator drew, the indoor layer too.
    public func destroy() {
        ready?.cancel()
        clearRoute()
        position = nil
        redrawDot()
        if let l = listener { map.removeIndoorLevelChangeListener(l) }
        listener = nil
        map.removeIndoor(options.id)
    }
}
#endif
